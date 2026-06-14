-- Enable PostGIS extension for spatial querying
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. Profiles Table
CREATE TABLE IF NOT EXISTS public.profiles (
    id uuid NOT NULL,
    email text NOT NULL UNIQUE,
    phone text NOT NULL UNIQUE,
    name text NOT NULL,
    role text DEFAULT 'producer'::text CHECK (role = ANY (ARRAY['producer'::text, 'extensionist'::text])),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT profiles_pkey PRIMARY KEY (id),
    CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);

-- 2. Fields Table
CREATE TABLE IF NOT EXISTS public.fields (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    producer_id uuid NOT NULL,
    name text NOT NULL,
    crop_type text NOT NULL CHECK (crop_type = ANY (ARRAY['milho'::text, 'soja'::text, 'algodao'::text])),
    planting_date date NOT NULL,
    boundary geography(POLYGON, 4326) NOT NULL,
    center geography(POINT, 4326) NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT fields_pkey PRIMARY KEY (id),
    CONSTRAINT fields_producer_id_fkey FOREIGN KEY (producer_id) REFERENCES public.profiles(id)
);

-- 3. Samplings Table
CREATE TABLE IF NOT EXISTS public.samplings (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    field_id uuid,
    observer_id uuid NOT NULL,
    species text NOT NULL,
    count integer NOT NULL CHECK (count >= 0),
    unit text NOT NULL,
    method text NOT NULL,
    location geography(POINT, 4326) NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    is_hidden boolean DEFAULT false,
    CONSTRAINT samplings_pkey PRIMARY KEY (id),
    CONSTRAINT samplings_observer_id_fkey FOREIGN KEY (observer_id) REFERENCES public.profiles(id),
    CONSTRAINT samplings_field_id_fkey FOREIGN KEY (field_id) REFERENCES public.fields(id)
);

-- 4. Risk Scores Table
CREATE TABLE IF NOT EXISTS public.risk_scores (
    field_id uuid NOT NULL,
    score integer NOT NULL CHECK (score >= 0 AND score <= 100),
    main_pest text,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT risk_scores_pkey PRIMARY KEY (field_id),
    CONSTRAINT risk_scores_field_id_fkey FOREIGN KEY (field_id) REFERENCES public.fields(id)
);

-- 5. Market Prices Table
CREATE TABLE IF NOT EXISTS public.market_prices (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    culture text NOT NULL UNIQUE CHECK (culture = ANY (ARRAY['milho'::text, 'soja'::text, 'algodao'::text])),
    price_per_sack numeric NOT NULL,
    source text NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT market_prices_pkey PRIMARY KEY (id)
);

-- 6. MIP Parameters Table
CREATE TABLE IF NOT EXISTS public.mip_parameters (
    culture text NOT NULL CHECK (culture = ANY (ARRAY['milho'::text, 'soja'::text, 'algodao'::text])),
    control_cost_per_ha numeric NOT NULL,
    efficacy_factor numeric NOT NULL DEFAULT 0.80,
    injury_factor numeric NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT mip_parameters_pkey PRIMARY KEY (culture)
);

-- 7. Users Table (for mirroring / extra context if applicable)
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL,
    email text NOT NULL UNIQUE,
    phone text NOT NULL UNIQUE,
    name text NOT NULL,
    role text DEFAULT 'producer'::text CHECK (role = ANY (ARRAY['producer'::text, 'extensionist'::text])),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);

-- 8. Alert Logs Table
CREATE TABLE IF NOT EXISTS public.alert_logs (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    pest_species text NOT NULL,
    severity text NOT NULL, -- 'amarelo', 'vermelho'
    message text NOT NULL,
    sent_at timestamp with time zone DEFAULT now(),
    CONSTRAINT alert_logs_pkey PRIMARY KEY (id)
);

-- 9. Weather Snapshots Table
CREATE TABLE IF NOT EXISTS public.weather_snapshots (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    municipality text NOT NULL,
    temperature numeric NOT NULL,
    humidity numeric NOT NULL,
    precipitation numeric NOT NULL,
    captured_at timestamp with time zone DEFAULT now(),
    CONSTRAINT weather_snapshots_pkey PRIMARY KEY (id)
);

-- Create spatial indices for fast GIST queries (optimizing radius operations)
CREATE INDEX IF NOT EXISTS idx_samplings_location ON public.samplings USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_fields_center ON public.fields USING GIST(center);

-- Trigger to automatically create a profile record when a new user registers in Supabase Auth
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, phone, name, role)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.phone, new.raw_user_meta_data->>'phone'),
    COALESCE(new.raw_user_meta_data->>'name', 'Usuário'),
    COALESCE(new.raw_user_meta_data->>'role', 'producer')
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Enable Row Level Security (RLS) policies
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fields ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.samplings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.risk_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Profiles are viewable by everyone" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can view their own fields" ON public.fields FOR SELECT USING (auth.uid() = producer_id);
CREATE POLICY "Users can insert their own fields" ON public.fields FOR INSERT WITH CHECK (auth.uid() = producer_id);
CREATE POLICY "Users can update their own fields" ON public.fields FOR UPDATE USING (auth.uid() = producer_id);
CREATE POLICY "Users can delete their own fields" ON public.fields FOR DELETE USING (auth.uid() = producer_id);

CREATE POLICY "Samplings are viewable by everyone" ON public.samplings FOR SELECT USING (true);
CREATE POLICY "Users can insert their own samplings" ON public.samplings FOR INSERT WITH CHECK (auth.uid() = observer_id);
CREATE POLICY "Users can update/delete their own samplings" ON public.samplings FOR UPDATE USING (auth.uid() = observer_id);

CREATE POLICY "Users can view risk scores for their fields" ON public.risk_scores FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.fields WHERE fields.id = risk_scores.field_id AND fields.producer_id = auth.uid())
);

CREATE POLICY "Users can view their own alert logs" ON public.alert_logs FOR SELECT USING (auth.uid() = profile_id);

-- --- RPC Functions for Edge Function ---

-- Function: get_regional_hotspots
-- Finds locations where at least `min_observers` have reported a pest focus within a `radius_meters` distance
CREATE OR REPLACE FUNCTION public.get_regional_hotspots(radius_meters double precision, min_observers integer)
RETURNS TABLE (
  location geography(POINT, 4326),
  pest_name text,
  observer_count bigint
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    s.location,
    s.species AS pest_name,
    COUNT(DISTINCT s.observer_id) AS observer_count
  FROM public.samplings s
  WHERE s.created_at >= NOW() - INTERVAL '7 days'
    AND s.is_hidden = false
  GROUP BY s.location, s.species
  HAVING COUNT(DISTINCT s.observer_id) >= min_observers;
END;
$$ LANGUAGE plpgsql;

-- Function: get_users_in_radius
-- Finds producers that own fields of crop `p_culture` within `radius_meters` of a center coordinate
CREATE OR REPLACE FUNCTION public.get_users_in_radius(
  center_loc geography(POINT, 4326),
  radius_meters double precision,
  p_culture text
)
RETURNS TABLE (
  user_name text,
  user_phone text,
  field_name text,
  distance_meters double precision
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.name AS user_name,
    p.phone AS user_phone,
    f.name AS field_name,
    ST_Distance(f.center, center_loc) AS distance_meters
  FROM public.fields f
  JOIN public.profiles p ON f.producer_id = p.id
  WHERE f.crop_type = p_culture
    AND ST_DWithin(f.center, center_loc, radius_meters)
  ORDER BY distance_meters ASC;
END;
$$ LANGUAGE plpgsql;
