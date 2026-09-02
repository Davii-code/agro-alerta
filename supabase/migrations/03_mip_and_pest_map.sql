-- 03_mip_and_pest_map.sql
--
-- RF04: the injury coefficient (I) and control cost (C) vary per pest, not per crop.
-- The original mip_parameters had `culture` as the sole primary key, so the database
-- path could only ever apply one set of C/K/I to every pest in a crop, while the
-- Python fallback dictionary was already indexed by crop AND pest. This migration
-- makes the table match the fallback.
--
-- It also adds pest_crop_map, which the notify-hotspot Edge Function needs to decide
-- which producers a given pest focus is relevant to.

-- ---------------------------------------------------------------------------
-- 1. mip_parameters: composite key (culture, pest_species)
-- ---------------------------------------------------------------------------

ALTER TABLE public.mip_parameters
  ADD COLUMN IF NOT EXISTS pest_species text NOT NULL DEFAULT '*';

COMMENT ON COLUMN public.mip_parameters.pest_species IS
  'Pest this row applies to. ''*'' is the per-crop wildcard used when no pest-specific row exists.';

ALTER TABLE public.mip_parameters DROP CONSTRAINT IF EXISTS mip_parameters_pkey;
ALTER TABLE public.mip_parameters
  ADD CONSTRAINT mip_parameters_pkey PRIMARY KEY (culture, pest_species);

-- Guard rails so a bad row cannot produce a nonsensical NDE.
ALTER TABLE public.mip_parameters DROP CONSTRAINT IF EXISTS mip_parameters_efficacy_range;
ALTER TABLE public.mip_parameters
  ADD CONSTRAINT mip_parameters_efficacy_range CHECK (efficacy_factor > 0 AND efficacy_factor <= 1);

ALTER TABLE public.mip_parameters DROP CONSTRAINT IF EXISTS mip_parameters_injury_positive;
ALTER TABLE public.mip_parameters
  ADD CONSTRAINT mip_parameters_injury_positive CHECK (injury_factor > 0);

ALTER TABLE public.mip_parameters DROP CONSTRAINT IF EXISTS mip_parameters_cost_positive;
ALTER TABLE public.mip_parameters
  ADD CONSTRAINT mip_parameters_cost_positive CHECK (control_cost_per_ha > 0);

-- Seed. These mirror MIP_FALLBACK_PARAMETERS in pipeline/ingestion_pipeline.py and
-- AgroDefaults in lib/services/mip_service.dart, so all three layers agree.
-- C = control cost (R$/ha), K = efficacy (0-1), I = injury coefficient.
INSERT INTO public.mip_parameters (culture, pest_species, control_cost_per_ha, efficacy_factor, injury_factor)
VALUES
  ('soja',    '*',                        130.00, 0.85, 0.15),
  ('soja',    'Lagarta-da-soja',          120.00, 0.90, 0.15),
  ('soja',    'Lagarta-do-cartucho',      130.00, 0.85, 0.18),
  ('soja',    'Percevejo-marrom',         150.00, 0.85, 0.80),
  ('milho',   '*',                        140.00, 0.82, 0.60),
  ('milho',   'Cigarrinha-do-milho',      140.00, 0.80, 1.20),
  ('milho',   'Lagarta-do-cartucho',      130.00, 0.85, 0.50),
  ('algodao', '*',                        200.00, 0.85, 1.50),
  ('algodao', 'Bicudo-do-algodoeiro',     200.00, 0.85, 2.50),
  ('algodao', 'Lagarta-do-cartucho',      180.00, 0.85, 1.10)
ON CONFLICT (culture, pest_species) DO UPDATE
  SET control_cost_per_ha = EXCLUDED.control_cost_per_ha,
      efficacy_factor     = EXCLUDED.efficacy_factor,
      injury_factor       = EXCLUDED.injury_factor,
      updated_at          = now();

-- ---------------------------------------------------------------------------
-- 2. pest_crop_map: which crops a pest threatens
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.pest_crop_map (
    pest_species text NOT NULL,
    culture text NOT NULL CHECK (culture = ANY (ARRAY['milho'::text, 'soja'::text, 'algodao'::text])),
    CONSTRAINT pest_crop_map_pkey PRIMARY KEY (pest_species, culture)
);

INSERT INTO public.pest_crop_map (pest_species, culture) VALUES
  ('Lagarta-do-cartucho',  'milho'),
  ('Lagarta-do-cartucho',  'soja'),
  ('Lagarta-do-cartucho',  'algodao'),
  ('Cigarrinha-do-milho',  'milho'),
  ('Percevejo-marrom',     'soja'),
  ('Lagarta-da-soja',      'soja'),
  ('Bicudo-do-algodoeiro', 'algodao')
ON CONFLICT DO NOTHING;

ALTER TABLE public.pest_crop_map ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Pest crop map is readable by everyone" ON public.pest_crop_map;
CREATE POLICY "Pest crop map is readable by everyone"
  ON public.pest_crop_map FOR SELECT USING (true);

-- ---------------------------------------------------------------------------
-- 3. Seed market prices so the app has a V (price per sack) on first run
-- ---------------------------------------------------------------------------

INSERT INTO public.market_prices (culture, price_per_sack, source)
VALUES
  ('soja',    129.71, 'CEPEA'),
  ('milho',    65.32, 'CEPEA'),
  ('algodao', 210.45, 'CEPEA')
ON CONFLICT (culture) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. alert_logs: columns the Edge Function needs for de-duplication
-- ---------------------------------------------------------------------------

-- Without a hotspot fingerprint the function re-notifies the same producers about
-- the same focus on every invocation.
ALTER TABLE public.alert_logs ADD COLUMN IF NOT EXISTS hotspot_key text;
ALTER TABLE public.alert_logs ADD COLUMN IF NOT EXISTS channel text NOT NULL DEFAULT 'whatsapp';
ALTER TABLE public.alert_logs ADD COLUMN IF NOT EXISTS delivery_status text NOT NULL DEFAULT 'pending';
ALTER TABLE public.alert_logs ADD COLUMN IF NOT EXISTS provider_response text;

COMMENT ON COLUMN public.alert_logs.hotspot_key IS
  'Stable id of the focus (pest + rounded coordinates). Used to suppress repeat alerts inside the cooldown window.';

CREATE INDEX IF NOT EXISTS idx_alert_logs_dedup
  ON public.alert_logs (profile_id, hotspot_key, sent_at DESC);
