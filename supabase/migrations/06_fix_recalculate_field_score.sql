-- Every sampling INSERT was failing on the server.
--
-- public.recalculate_field_score() runs AFTER INSERT ON public.samplings and
-- started with `SELECT crop_type, location FROM public.fields`. public.fields
-- has no `location` column - it has `boundary` and `center` - so the statement
-- raised 42703 "column location does not exist" and took the INSERT down with
-- it. The app's sync swallowed the error and kept the sampling queued, so the
-- producer saw a pending badge that never cleared and no sampling ever reached
-- the server.
--
-- Two more things were off in the same function:
--
--   * mip_parameters got a composite key (culture, pest_species) in migration
--     03, but the lookup still filtered by culture alone, so SELECT INTO picked
--     whichever row came first and the NDE used the wrong pest's numbers.
--     It now looks up the sampled species and falls back to the '*' wildcard,
--     which is what MipService does in the app.
--
--   * samplings.field_id is nullable. A sampling with no field cannot have a
--     field score, and the function went on to INSERT INTO risk_scores with a
--     NULL field_id, violating the primary key. It returns early instead.
CREATE OR REPLACE FUNCTION public.recalculate_field_score()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_count INTEGER;
    v_main_pest TEXT;
    v_culture TEXT;
    v_field_location GEOGRAPHY(POINT, 4326);
    v_price_v NUMERIC;
    v_cost_c NUMERIC;
    v_eff_k NUMERIC;
    v_inj_i NUMERIC;
    v_nde_limit NUMERIC;
    v_score_value INTEGER;
BEGIN
    -- Sampling without a field: nothing to score.
    IF NEW.field_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- A. Cultura e localizacao do talhao. `center` e a coluna que existe.
    SELECT crop_type, center INTO v_culture, v_field_location
    FROM public.fields
    WHERE id = NEW.field_id;

    IF v_culture IS NULL THEN
        RETURN NEW;
    END IF;

    -- B. Variaveis da formula (C, K, V, I).
    SELECT price_per_sack INTO v_price_v
    FROM public.market_prices
    WHERE culture = v_culture;

    -- Parametro da praga amostrada; '*' e o padrao por cultura.
    SELECT control_cost_per_ha, efficacy_factor, injury_factor
    INTO v_cost_c, v_eff_k, v_inj_i
    FROM public.mip_parameters
    WHERE culture = v_culture
      AND pest_species = NEW.species;

    IF v_cost_c IS NULL THEN
        SELECT control_cost_per_ha, efficacy_factor, injury_factor
        INTO v_cost_c, v_eff_k, v_inj_i
        FROM public.mip_parameters
        WHERE culture = v_culture
          AND pest_species = '*';
    END IF;

    -- C. NDE = (C * K) / (V * I)
    IF v_price_v IS NULL OR v_price_v = 0
       OR v_inj_i IS NULL OR v_inj_i = 0
       OR v_cost_c IS NULL OR v_eff_k IS NULL THEN
        v_nde_limit := 10;
    ELSE
        v_nde_limit := (v_cost_c * v_eff_k) / (v_price_v * v_inj_i);
    END IF;

    -- D. Amostragem total (ultimas 24h num raio de 20km) - RN 05
    SELECT COALESCE(SUM(s.count), 0) INTO v_total_count
    FROM public.samplings s
    JOIN public.fields f ON s.field_id = f.id
    WHERE f.crop_type = v_culture
      AND ST_DWithin(s.location, v_field_location, 20000)
      AND s.created_at > NOW() - INTERVAL '24 hours';

    -- E. Praga principal no raio de 20km
    SELECT s.species INTO v_main_pest
    FROM public.samplings s
    JOIN public.fields f ON s.field_id = f.id
    WHERE f.crop_type = v_culture
      AND ST_DWithin(s.location, v_field_location, 20000)
      AND s.created_at > NOW() - INTERVAL '24 hours'
    ORDER BY s.created_at DESC
    LIMIT 1;

    -- F. Score a partir do NDE
    IF v_nde_limit IS NULL OR v_nde_limit <= 0 THEN
        v_score_value := 0;
    ELSIF v_total_count >= v_nde_limit THEN
        v_score_value := 100;
    ELSE
        v_score_value := LEAST(ROUND((v_total_count / v_nde_limit) * 100), 100);
    END IF;

    -- G. Persistir o score
    INSERT INTO public.risk_scores (field_id, score, main_pest, updated_at)
    VALUES (NEW.field_id, v_score_value, v_main_pest, NOW())
    ON CONFLICT (field_id)
    DO UPDATE SET
        score = EXCLUDED.score,
        main_pest = EXCLUDED.main_pest,
        updated_at = EXCLUDED.updated_at;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.recalculate_field_score IS
'Recalcula risk_scores a cada amostragem. Le fields.center (nao fields.location,
que nunca existiu) e resolve mip_parameters por (culture, pest_species) com
fallback no curinga ''*''.';
