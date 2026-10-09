import os
import sys
from datetime import datetime, timedelta, timezone
import pandas as pd
import requests
from dotenv import load_dotenv
from supabase import create_client, Client

# Load environment variables
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "https://your-project.supabase.co")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "your-anon-or-service-key")

# WhatsApp delivery is delegated to the Edge Functions so there is exactly one
# code path that talks to a provider. Without these the pipeline prints instead.
EDGE_FUNCTION_URL = os.getenv("SUPABASE_FUNCTIONS_URL", "").rstrip("/")
CRON_SECRET = os.getenv("CRON_SECRET", "")

# Initialize Supabase Client
try:
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
except Exception as e:
    print(f"Error initializing Supabase client: {e}")
    supabase = None

# Default local fallback parameters for Crops & Pests (MIP constants)
# C = Cost of control (R$/ha), K = Control efficiency (0.0 to 1.0), I = Injury coefficient
MIP_FALLBACK_PARAMETERS = {
    # Pest keys match the picker in lib/screens/new_sampling_screen.dart exactly;
    # a mismatch here silently falls through to the "*" wildcard.
    # "*" is the per-crop default, mirroring mip_parameters in migration 03.
    "soja": {
        "*":                    {"C": 130.00, "K": 0.85, "I": 0.15},
        "Lagarta-da-soja":      {"C": 120.00, "K": 0.90, "I": 0.15},
        "Lagarta-do-cartucho":  {"C": 130.00, "K": 0.85, "I": 0.18},
        "Percevejo-marrom":     {"C": 150.00, "K": 0.85, "I": 0.80}
    },
    "milho": {
        "*":                    {"C": 140.00, "K": 0.82, "I": 0.60},
        "Cigarrinha-do-milho":  {"C": 140.00, "K": 0.80, "I": 1.20},
        "Lagarta-do-cartucho":  {"C": 130.00, "K": 0.85, "I": 0.50}
    },
    "algodao": {
        "*":                    {"C": 200.00, "K": 0.85, "I": 1.50},
        "Bicudo-do-algodoeiro": {"C": 200.00, "K": 0.85, "I": 2.50},
        "Lagarta-do-cartucho":  {"C": 180.00, "K": 0.85, "I": 1.10}
    }
}

# Fallback prices used only when market_prices is empty. Kept identical to
# _bundledPrices in lib/services/mip_service.dart and to the seed in
# supabase/migrations/03_mip_and_pest_map.sql - a different V here means the
# app and the pipeline compute a different NDE for the same field.
DEFAULT_PRICES = {
    "soja": 129.71,
    "milho": 65.32,
    "algodao": 210.45
}

# What each crop's number means once it lands in market_prices.price_per_sack.
# Soja and milho are quoted per 60 kg sack, so the column name is literal.
# Algodao has no sack: CEPEA quotes it in centavos de real per pound, and the
# app's bundled 210.45 was a R$/arroba figure, so arroba is the target here.
CEPEA_TARGET_UNIT = {
    "soja": "sc60kg",
    "milho": "sc60kg",
    "algodao": "@15kg",
}

# Published CEPEA unit -> factor that converts it into CEPEA_TARGET_UNIT.
# Verified against agrobr 1.1.0 live responses: soja and milho come as
# "BRL/sc60kg", algodao as "cBRL/lb". A unit missing from here is refused by
# fetch_market_prices rather than persisted, because the column carries no unit
# of its own and a wrong one silently rescales every NDE in the app.
CEPEA_UNIT_TO_SACK = {
    "soja": {"BRL/sc60kg": 1.0},
    "milho": {"BRL/sc60kg": 1.0},
    # centavos/lb -> R$/@: /100, then 2.2046226 lb per kg, then 15 kg per arroba.
    "algodao": {"cBRL/lb": 2.2046226 * 15 / 100},
}

# NASA POWER publishes a day's values a few days late, and fills the gap with
# rows whose columns are all NaN. Asking only for today therefore returns a row
# that looks present and is empty, which is how this pipeline ended up writing
# 25.0 C / 70% for every municipality. Look back far enough to land on a day
# that is actually filled in.
NASA_LOOKBACK_DAYS = 10

def fetch_market_prices():
    """
    Fetch crop prices from the CEPEA/ESALQ indicator via agrobr.

    This used to call conab.safras(crop, state="GO") and read a "preco" column.
    That was wrong twice over: the keyword is `uf`, not `state`, and safras()
    returns area/producao/produtividade - CONAB publishes no price there. So the
    call always raised and every crop silently fell back to DEFAULT_PRICES,
    which meant the NDE in the app was computed from a constant.

    CEPEA is the reference price series for these three crops. Only the units
    listed in CEPEA_UNIT_TO_SACK are accepted; anything else keeps the fallback
    instead of persisting a number in the wrong unit, which would move every
    NDE without any visible error.
    """
    prices = DEFAULT_PRICES.copy()
    sources = {crop: "valor de referência" for crop in prices}

    try:
        from agrobr.sync import cepea
    except Exception as import_err:
        print(f"CEPEA unavailable, keeping bundled prices: {import_err}")
        cepea = None

    if cepea is not None:
        for crop in prices:
            try:
                indicator = cepea.ultimo(crop)
                unit = indicator.unidade
                factor = CEPEA_UNIT_TO_SACK.get(crop, {}).get(unit)
                if factor is None:
                    print(
                        f"CEPEA {crop}: unidade inesperada {unit!r}, "
                        f"mantendo R$ {prices[crop]:.2f} do fallback."
                    )
                    continue
                prices[crop] = float(indicator.valor) * factor
                # Short on purpose: HomeScreen prints this under the price in
                # a chip, and a long string stretched the chip off screen.
                sources[crop] = f"CEPEA/ESALQ · R$/{CEPEA_TARGET_UNIT[crop]}"
                print(
                    f"CEPEA {crop}: {indicator.valor} {unit} "
                    f"-> R$ {prices[crop]:.2f}/{CEPEA_TARGET_UNIT[crop]} "
                    f"({indicator.data}, {indicator.praca})"
                )
            except Exception as err:
                print(f"CEPEA {crop} falhou ({type(err).__name__}: {err}), mantendo fallback.")

    # Save to Supabase market_prices table (Aligned with your schema)
    if supabase:
        for crop, price in prices.items():
            try:
                # Select existing to decide insert or update
                existing = supabase.table("market_prices").select("id").eq("culture", crop).execute()

                data = {
                    "culture": crop,
                    "price_per_sack": round(price, 2),
                    # There is no unit column, so the unit rides along in source.
                    # Without it a reader cannot tell R$/saca from R$/arroba.
                    "source": sources[crop],
                    "updated_at": datetime.now(timezone.utc).isoformat()
                }

                if existing.data:
                    record_id = existing.data[0]["id"]
                    supabase.table("market_prices").update(data).eq("id", record_id).execute()
                else:
                    supabase.table("market_prices").insert(data).execute()

                print(f"Persisted market price: {crop} -> R$ {price:.2f} [{sources[crop]}]")
            except Exception as db_err:
                print(f"Error persisting price to database: {db_err}")

    return prices

# Coordinates of the municipalities sampled every run.
MUNICIPALITY_COORDS = {
    "Anapolis": (-16.32, -48.95),
    "Rio Verde": (-17.79, -50.92),
    "Jatai": (-17.88, -51.72),
    "Neropolis": (-16.40, -49.21),
}


def fetch_weather_snapshots():
    """
    Fetch weather snapshots for major municipalities in Goiás via NASA POWER.

    Two bugs used to make every municipality report an identical 25.0 C / 70%:
    the columns were read as "temperature"/"humidity"/"precipitation" while
    agrobr returns "temp_media"/"umidade_rel"/"precip_mm", so .get() handed back
    the placeholder defaults; and the window was today-to-today, which NASA
    POWER answers with an all-NaN row because its daily series runs a few days
    behind. Both failures were silent - .get() has no way to say "missing".

    A municipality with no usable day is now skipped rather than written with a
    made-up number, so weather_snapshots only ever holds measured values.
    """
    weather_data = []

    try:
        from agrobr.sync import nasa_power
    except Exception as import_err:
        print(f"NASA POWER unavailable, no weather snapshot written: {import_err}")
        return weather_data

    today = datetime.now(timezone.utc).date()
    start = today - timedelta(days=NASA_LOOKBACK_DAYS)

    for muni, (lat, lon) in MUNICIPALITY_COORDS.items():
        try:
            print(f"Fetching NASA POWER weather for {muni} via agrobr...")
            df = nasa_power.clima_ponto(
                lat=lat,
                lon=lon,
                inicio=start.isoformat(),
                fim=today.isoformat(),
            )
            if df is None or df.empty:
                print(f"{muni}: NASA POWER returned no rows, skipping.")
                continue

            # Most recent day that carries both readings. dropna on the two
            # required columns is what separates a real measurement from the
            # NaN placeholder rows at the end of the series.
            usable = df.dropna(subset=["temp_media", "umidade_rel"]).sort_values("data")
            if usable.empty:
                print(
                    f"{muni}: nenhum dia preenchido nos ultimos "
                    f"{NASA_LOOKBACK_DAYS} dias, pulando."
                )
                continue

            row = usable.iloc[-1]
            temp = float(row["temp_media"])
            hum = float(row["umidade_rel"])
            # Precipitation can legitimately be absent on a day that has
            # temperature; a dry day is 0.0 mm, so that default is a fact.
            prec_raw = row.get("precip_mm")
            prec = 0.0 if prec_raw is None or pd.isna(prec_raw) else float(prec_raw)
            captured_at = pd.Timestamp(row["data"]).tz_localize("UTC").isoformat()
        except Exception as e:
            print(f"Weather fetch failed for {muni} ({type(e).__name__}: {e}), skipping.")
            continue

        weather_data.append({
            "municipality": muni,
            "temperature": temp,
            "humidity": hum,
            "precipitation": prec,
        })

        # Save to database
        if supabase:
            try:
                supabase.table("weather_snapshots").insert({
                    "municipality": muni,
                    "temperature": temp,
                    "humidity": hum,
                    "precipitation": prec,
                    # The day the measurement refers to, not the run time: the
                    # series lags, and a row stamped "now" would misdate it.
                    "captured_at": captured_at,
                }).execute()
                print(
                    f"Persisted weather snapshot: {muni} -> "
                    f"{row['data'].date()} Temp: {temp:.1f}C, Hum: {hum:.1f}%, "
                    f"Prec: {prec:.1f}mm"
                )
            except Exception as db_err:
                print(f"Error persisting weather to database: {db_err}")

    return weather_data

def run_calculations_and_rules():
    """
    Recalculate NDE and Risk Scores for all active fields in Supabase.
    """
    if not supabase:
        print("Supabase client is not available. Skipping calculations.")
        return

    print("Running Risk and Economic Injury Level calculations...")
    
    # 1. Fetch current market prices
    prices_res = supabase.table("market_prices").select("culture, price_per_sack").order("updated_at", desc=True).execute()
    prices = {p["culture"]: float(p["price_per_sack"]) for p in prices_res.data} if prices_res.data else DEFAULT_PRICES
    
    # 2. Fetch MIP Parameters from DB
    mip_res = supabase.table("mip_parameters").select("*").execute()
    # Keyed by (culture, pest_species) so the per-pest rows added in migration 03
    # are actually reachable. The old dict was keyed by culture alone, so every
    # pest in a crop silently shared one injury coefficient.
    db_mip = {}
    for m in (mip_res.data or []):
        db_mip[(m["culture"], m.get("pest_species", "*"))] = m

    # 3. Fetch all fields
    fields_res = supabase.table("fields").select("*").execute()
    fields = fields_res.data if fields_res.data else []
    
    for field in fields:
        field_id = field["id"]
        crop_type = field["crop_type"]
        
        # Get latest sampling for this field
        samplings_res = supabase.table("samplings").select("*").eq("field_id", field_id).order("created_at", desc=True).limit(1).execute()
        
        if not samplings_res.data:
            supabase.table("risk_scores").upsert({
                "field_id": field_id,
                "score": 10,
                "main_pest": "Nenhuma",
                "updated_at": datetime.now(timezone.utc).isoformat()
            }).execute()
            continue
            
        latest_sampling = samplings_res.data[0]
        pest_species = latest_sampling["species"]
        pest_count = latest_sampling["count"]
        
        # Resolve C, K, I. Most specific source wins: exact pest row from the
        # database, then the '*' wildcard row for the crop, then the local
        # fallback table. Kept in step with MipService.parametersFor() in Dart.
        row = db_mip.get((crop_type, pest_species)) or db_mip.get((crop_type, "*"))
        if row:
            C = float(row["control_cost_per_ha"])
            K = float(row["efficacy_factor"])
            I = float(row["injury_factor"])
        else:
            crop_params = MIP_FALLBACK_PARAMETERS.get(crop_type, {})
            pest_params = crop_params.get(
                pest_species,
                crop_params.get("*", {"C": 150.00, "K": 0.85, "I": 1.0}),
            )
            C = pest_params["C"]
            K = pest_params["K"]
            I = pest_params["I"]

        V = prices.get(crop_type, DEFAULT_PRICES.get(crop_type, 100.00))
        
        # Calculate Economic Injury Level (NDE)
        # NDE = (C * K) / (V * I)
        nde = (C * K) / (V * I)
        
        print(f"Field: {field['name']} ({crop_type}) | Pest: {pest_species} | Count: {pest_count} | Calculated NDE: {nde:.4f}")
        
        # Determine Score of Risk (0-100)
        if pest_count >= nde:
            score = 100
        else:
            # Same linear scale as RiskCalculator.scoreFor in Dart. The old *70
            # factor meant the pipeline could never emit a value between 71 and
            # 99, so it disagreed with the app about the Yellow/Red boundary.
            score = int(round((pest_count / nde) * 100))
            score = min(max(score, 1), 99)
            
        # Update risk_scores table
        supabase.table("risk_scores").upsert({
            "field_id": field_id,
            "score": score,
            "main_pest": pest_species,
            "updated_at": datetime.now(timezone.utc).isoformat()
        }).execute()
        
        # Trigger mock WhatsApp alert if score is critical (RED/100)
        if score == 100:
            trigger_whatsapp_alert(field, pest_species, pest_count, nde)

def trigger_whatsapp_alert(field, pest, count, nde):
    """
    Notifies the producer that their own field crossed the economic threshold.

    Delivery is delegated to the notify-hotspot Edge Function so there is a single
    place that talks to WhatsApp. This used to print() the message and log it,
    which meant the pipeline claimed to alert without ever sending anything.

    Falls back to printing when the function is not configured, so a local run
    with no credentials still shows what would have gone out.
    """
    producer_id = field["producer_id"]
    profile_res = supabase.table("profiles").select("*").eq("id", producer_id).execute()

    if not profile_res.data:
        return

    profile = profile_res.data[0]
    phone = profile.get("phone") or "Não cadastrado"
    name = profile.get("name") or "Produtor"

    message = (
        f"*AGRO ALERTA GO*\n\n"
        f"Olá, {name}!\n"
        f"A contagem de *{pest}* no seu talhão *{field['name']}* chegou a *{count}*, "
        f"acima do ponto de prejuízo calculado ({nde:.0f}).\n\n"
        f"*Recomendação:* a aplicação já se paga. Fale com seu extensionista."
    )

    sent = False
    detail = "edge function não configurada"

    if EDGE_FUNCTION_URL and CRON_SECRET:
        try:
            response = requests.post(
                f"{EDGE_FUNCTION_URL}/notify-producer",
                headers={
                    "Content-Type": "application/json",
                    "x-cron-secret": CRON_SECRET,
                },
                json={
                    "profile_id": producer_id,
                    "phone": phone,
                    "name": name,
                    "pest": pest,
                    "field_name": field["name"],
                    "count": count,
                    "nde": round(nde, 2),
                },
                timeout=20,
            )
            sent = response.ok
            detail = response.text[:500]
        except Exception as err:
            detail = str(err)

    if not sent:
        print("\n--- WHATSAPP (não enviado) ---")
        print(f"Para: {phone}")
        print(f"Motivo: {detail}")
        print(f"Mensagem:\n{message}")
        print("------------------------------\n")

    # alert_logs is the audit trail: record the attempt either way, with the
    # outcome, instead of logging every message as if it had been delivered.
    try:
        supabase.table("alert_logs").insert({
            "profile_id": producer_id,
            "pest_species": pest,
            "severity": "vermelho",
            "message": message,
            "hotspot_key": f"field:{field['id']}",
            "channel": "whatsapp" if sent else "pipeline-dry-run",
            "delivery_status": "sent" if sent else "failed",
            "provider_response": detail[:1000],
            "sent_at": datetime.now(timezone.utc).isoformat()
        }).execute()
    except Exception as e:
        print(f"Failed to log alert message: {e}")


def notify_regional_hotspots():
    """
    Asks the notify-hotspot Edge Function to run the regional pass (RF06 + RN14).

    The pipeline deliberately does not duplicate the clustering or the WhatsApp
    call: both live in the function, which is also what the cron schedule hits.
    """
    if not (EDGE_FUNCTION_URL and CRON_SECRET):
        print("Regional alerts skipped: SUPABASE_FUNCTIONS_URL/CRON_SECRET não definidos.")
        return

    try:
        response = requests.post(
            f"{EDGE_FUNCTION_URL}/notify-hotspot",
            headers={
                "Content-Type": "application/json",
                "x-cron-secret": CRON_SECRET,
            },
            json={},
            timeout=60,
        )
        print(f"Regional alerts: HTTP {response.status_code} -> {response.text[:800]}")
    except Exception as err:
        print(f"Regional alerts failed: {err}")


if __name__ == "__main__":
    print("Starting Ingestion Pipeline...")
    fetch_market_prices()
    fetch_weather_snapshots()
    run_calculations_and_rules()
    notify_regional_hotspots()
    print("Ingestion Pipeline execution finished.")
