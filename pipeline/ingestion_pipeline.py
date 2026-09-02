import os
import sys
from datetime import datetime, timezone
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

def fetch_market_prices():
    """
    Fetch crop prices from CONAB using agrobr library.
    Falls back to hardcoded default values if library or API fails.
    """
    prices = DEFAULT_PRICES.copy()
    try:
        from agrobr.sync import conab
        print("Fetching prices via agrobr...")
        for crop in prices.keys():
            df = conab.safras(crop, state="GO")
            if df is not None and not df.empty:
                latest_price = df.iloc[0].get("preco", prices[crop])
                prices[crop] = float(latest_price)
                print(f"CONAB price for {crop}: R$ {prices[crop]:.2f}")
    except Exception as e:
        print(f"CONAB Ingestion fallback (using mock/default values) due to: {e}")
    
    # Save to Supabase market_prices table (Aligned with your schema)
    if supabase:
        for crop, price in prices.items():
            try:
                # Select existing to decide insert or update
                existing = supabase.table("market_prices").select("id").eq("culture", crop).execute()
                
                data = {
                    "culture": crop,
                    "price_per_sack": price,
                    "source": "CONAB",
                    "updated_at": datetime.now(timezone.utc).isoformat()
                }
                
                if existing.data:
                    record_id = existing.data[0]["id"]
                    supabase.table("market_prices").update(data).eq("id", record_id).execute()
                else:
                    supabase.table("market_prices").insert(data).execute()
                    
                print(f"Persisted market price: {crop} -> R$ {price:.2f}")
            except Exception as db_err:
                print(f"Error persisting price to database: {db_err}")
                
    return prices

def fetch_weather_snapshots():
    """
    Fetch weather snapshots for major municipalities in Goiás using INMET/NASA Power via agrobr.
    """
    municipalities = ["Anapolis", "Rio Verde", "Jatai", "Neropolis"]
    weather_data = []
    
    for muni in municipalities:
        temp, hum, prec = 25.0, 70.0, 5.0
        try:
            from agrobr.sync import nasa_power
            print(f"Fetching NASA Power weather for {muni} via agrobr...")
            coords = {"Anapolis": (-16.32, -48.95), "Rio Verde": (-17.79, -50.92), "Jatai": (-17.88, -51.72), "Neropolis": (-16.40, -49.21)}
            lat, lon = coords[muni]
            df = nasa_power.clima_ponto(lat=lat, lon=lon, inicio=datetime.now().strftime("%Y-%m-%d"), fim=datetime.now().strftime("%Y-%m-%d"))
            if df is not None and not df.empty:
                temp = float(df.iloc[0].get("temperature", temp))
                hum = float(df.iloc[0].get("humidity", hum))
                prec = float(df.iloc[0].get("precipitation", prec))
        except Exception as e:
            print(f"Weather Ingestion fallback for {muni} due to: {e}")
            
        weather_data.append({
            "municipality": muni,
            "temperature": temp,
            "humidity": hum,
            "precipitation": prec
        })
        
        # Save to database
        if supabase:
            try:
                supabase.table("weather_snapshots").insert({
                    "municipality": muni,
                    "temperature": temp,
                    "humidity": hum,
                    "precipitation": prec,
                    "captured_at": datetime.now(timezone.utc).isoformat()
                }).execute()
                print(f"Persisted weather snapshot: {muni} -> Temp: {temp}C, Hum: {hum}%")
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
