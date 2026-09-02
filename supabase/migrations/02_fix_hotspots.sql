-- 02_fix_hotspots.sql
--
-- Fixes RF06 (regional pest focus validation).
--
-- The original get_regional_hotspots() declared `radius_meters` and never used it:
-- it did `GROUP BY s.location`, which compares geography values for binary equality.
-- Two producers standing 10 m apart produced two separate groups of one observer
-- each, so `HAVING COUNT(DISTINCT observer_id) >= 2` could never fire unless the
-- coordinates matched bit for bit.
--
-- This version clusters with ST_ClusterDBSCAN over the 7-day window, so "2+ distinct
-- observers within `radius_meters`" is evaluated the way the requirement describes.
--
-- It also changes the return shape: latitude and longitude come back as plain
-- numerics instead of a geography column. PostgREST serialises geography as GeoJSON,
-- and that object cannot be fed back into a `geography` RPC parameter - which is
-- exactly what the notify-hotspot Edge Function was trying to do.

-- The signature changes, so drop the old one explicitly.
DROP FUNCTION IF EXISTS public.get_regional_hotspots(double precision, integer);

CREATE OR REPLACE FUNCTION public.get_regional_hotspots(
  radius_meters double precision DEFAULT 5000,
  min_observers integer DEFAULT 2,
  window_days integer DEFAULT 7
)
RETURNS TABLE (
  cluster_id integer,
  pest_name text,
  crop_type text,
  observer_count bigint,
  sampling_count bigint,
  total_specimens bigint,
  latitude double precision,
  longitude double precision,
  last_seen timestamp with time zone
)
LANGUAGE sql
STABLE
AS $$
  WITH recent AS (
    SELECT
      s.species,
      s.observer_id,
      s.count,
      s.created_at,
      s.location,
      f.crop_type,
      -- ST_ClusterDBSCAN is a window function: it labels each row with a cluster id.
      -- eps uses the units of the input geometry, so the point is reprojected to
      -- 3857 (metres) and eps can stay expressed in metres.
      ST_ClusterDBSCAN(
        ST_Transform(s.location::geometry, 3857),
        eps := radius_meters,
        minpoints := 1
      ) OVER (PARTITION BY s.species) AS cid
    FROM public.samplings s
    LEFT JOIN public.fields f ON f.id = s.field_id
    WHERE s.created_at >= NOW() - (window_days || ' days')::interval
      AND s.is_hidden = false
      AND s.count > 0
  )
  SELECT
    r.cid AS cluster_id,
    r.species AS pest_name,
    -- Dominant crop inside the cluster, so the Edge Function notifies the right
    -- producers instead of hardcoding 'soja'.
    COALESCE(mode() WITHIN GROUP (ORDER BY r.crop_type), 'soja') AS crop_type,
    COUNT(DISTINCT r.observer_id) AS observer_count,
    COUNT(*) AS sampling_count,
    SUM(r.count)::bigint AS total_specimens,
    ST_Y(ST_Centroid(ST_Collect(r.location::geometry))) AS latitude,
    ST_X(ST_Centroid(ST_Collect(r.location::geometry))) AS longitude,
    MAX(r.created_at) AS last_seen
  FROM recent r
  WHERE r.cid IS NOT NULL
  GROUP BY r.cid, r.species
  HAVING COUNT(DISTINCT r.observer_id) >= min_observers
  ORDER BY COUNT(DISTINCT r.observer_id) DESC, MAX(r.created_at) DESC;
$$;

COMMENT ON FUNCTION public.get_regional_hotspots IS
  'RF06: pest focuses confirmed by >= min_observers distinct observers clustered within radius_meters over the last window_days.';


-- get_users_in_radius now takes plain coordinates and builds the point itself.
-- Passing a GeoJSON object into a geography parameter over PostgREST does not cast.
DROP FUNCTION IF EXISTS public.get_users_in_radius(geography, double precision, text);

CREATE OR REPLACE FUNCTION public.get_users_in_radius(
  p_lat double precision,
  p_lon double precision,
  radius_meters double precision DEFAULT 20000,
  p_culture text DEFAULT NULL
)
RETURNS TABLE (
  profile_id uuid,
  user_name text,
  user_phone text,
  field_name text,
  crop_type text,
  distance_meters double precision
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    p.id AS profile_id,
    p.name AS user_name,
    p.phone AS user_phone,
    f.name AS field_name,
    f.crop_type,
    ST_Distance(f.center, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography) AS distance_meters
  FROM public.fields f
  JOIN public.profiles p ON p.id = f.producer_id
  -- NULL culture means "every crop", used when the hotspot crop is unknown.
  WHERE (p_culture IS NULL OR f.crop_type = p_culture)
    AND ST_DWithin(f.center, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography, radius_meters)
  -- The expression is repeated instead of ordering by the `distance_meters`
  -- alias: in a LANGUAGE sql function the RETURNS TABLE columns are also OUT
  -- parameters in scope, and referencing one by name here raises
  -- "column reference distance_meters is ambiguous" (42702).
  ORDER BY ST_Distance(f.center, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography) ASC;
$$;

COMMENT ON FUNCTION public.get_users_in_radius IS
  'RN14: producers whose field centroid falls within radius_meters of a confirmed hotspot.';


-- Producers must be able to read their own risk score. The original policy only
-- allowed SELECT; the app now upserts the score it computes locally so the value
-- survives a reinstall and matches what the Python pipeline writes.
DROP POLICY IF EXISTS "Users can write risk scores for their fields" ON public.risk_scores;
CREATE POLICY "Users can write risk scores for their fields"
  ON public.risk_scores FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.fields f
             WHERE f.id = risk_scores.field_id AND f.producer_id = auth.uid())
  );

DROP POLICY IF EXISTS "Users can update risk scores for their fields" ON public.risk_scores;
CREATE POLICY "Users can update risk scores for their fields"
  ON public.risk_scores FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.fields f
             WHERE f.id = risk_scores.field_id AND f.producer_id = auth.uid())
  );

-- Market prices and MIP parameters are reference data: readable by any signed-in
-- user, writable only by the service role (the Python pipeline).
ALTER TABLE public.market_prices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mip_parameters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weather_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Market prices are readable by everyone" ON public.market_prices;
CREATE POLICY "Market prices are readable by everyone"
  ON public.market_prices FOR SELECT USING (true);

DROP POLICY IF EXISTS "MIP parameters are readable by everyone" ON public.mip_parameters;
CREATE POLICY "MIP parameters are readable by everyone"
  ON public.mip_parameters FOR SELECT USING (true);

DROP POLICY IF EXISTS "Weather is readable by everyone" ON public.weather_snapshots;
CREATE POLICY "Weather is readable by everyone"
  ON public.weather_snapshots FOR SELECT USING (true);
