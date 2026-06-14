import os
import sys
from datetime import datetime
from dotenv import load_dotenv
from supabase import create_client, Client

# Load environment variables
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "https://your-project.supabase.co")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "your-anon-or-service-key")

# Initialize Supabase Client
try:
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
except Exception as e:
    print(f"Error initializing Supabase client: {e}")
    supabase = None

# Default local fallback parameters for Crops & Pests (MIP constants)
# C = Cost of control (R$/ha), K = Control efficiency (0.0 to 1.0), I = Injury coefficient
MIP_FALLBACK_PARAMETERS = {
    "soja": {
        "Lagarta da Soja": {"C": 120.00, "K": 0.90, "I": 0.15},
        "Percevejo Marrom": {"C": 150.00, "K": 0.85, "I": 0.80}
    },
    "milho": {
        "Cigarrinha do Milho": {"C": 140.00, "K": 0.80, "I": 1.20},
        "Lagarta do Cartucho": {"C": 130.00, "K": 0.85, "I": 0.50}
    },
    "algodao": {
        "Bicudo do Algodoeiro": {"C": 200.00, "K": 0.85, "I": 2.50}
    }
}

DEFAULT_PRICES = {
    "soja": 135.50,
    "milho": 58.20,
    "algodao": 240.00
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
                    "updated_at": datetime.utcnow().isoformat()
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
                    "captured_at": datetime.utcnow().isoformat()
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
    db_mip = {m["culture"]: m for m in mip_res.data} if mip_res.data else {}

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
                "updated_at": datetime.utcnow().isoformat()
            }).execute()
            continue
            
        latest_sampling = samplings_res.data[0]
        pest_species = latest_sampling["species"]
        pest_count = latest_sampling["count"]
        
        # Resolve C, K, I parameters
        if crop_type in db_mip:
            # Use real database variables
            C = float(db_mip[crop_type]["control_cost_per_ha"])
            K = float(db_mip[crop_type]["efficacy_factor"])
            I = float(db_mip[crop_type]["injury_factor"])
        else:
            # Fallback to local config
            crop_params = MIP_FALLBACK_PARAMETERS.get(crop_type, {})
            pest_params = crop_params.get(pest_species, {"C": 150.00, "K": 0.85, "I": 1.0})
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
            score = int((pest_count / nde) * 70)
            score = min(max(score, 0), 99)
            
        # Update risk_scores table
        supabase.table("risk_scores").upsert({
            "field_id": field_id,
            "score": score,
            "main_pest": pest_species,
            "updated_at": datetime.utcnow().isoformat()
        }).execute()
        
        # Trigger mock WhatsApp alert if score is critical (RED/100)
        if score == 100:
            trigger_whatsapp_alert(field, pest_species, pest_count, nde)

def trigger_whatsapp_alert(field, pest, count, nde):
    """
    Simulates sending a WhatsApp Alert when infestation is critical (RN 11 / RI 01).
    """
    producer_id = field["producer_id"]
    profile_res = supabase.table("profiles").select("*").eq("id", producer_id).execute()
    
    if not profile_res.data:
        return
        
    profile = profile_res.data[0]
    phone = profile.get("phone", "Não cadastrado")
    name = profile.get("name", "Produtor")
    
    message = (
        f"🚨 *ALERTA AGRO-ALERTA* 🚨\n\n"
        f"Olá, {name}!\n"
        f"Identificamos uma infestação crítica no seu talhão *{field['name']}*.\n"
        f"A contagem de *{pest}* atingiu *{count}*, superando o Nível de Dano Econômico calculado de *{nde:.2f}*.\n\n"
        f"💡 *Recomendação:* A aplicação química é financeiramente viável no momento. Consulte o seu extensionista associado."
    )
    
    print(f"\n--- WHATSAPP NOTIFICATION SENT ---")
    print(f"To: {phone}")
    print(f"Message:\n{message}")
    print(f"----------------------------------\n")
    
    # Log sent alert in alert_logs table
    try:
        supabase.table("alert_logs").insert({
            "profile_id": producer_id,
            "pest_species": pest,
            "severity": "vermelho",
            "message": message,
            "sent_at": datetime.utcnow().isoformat()
        }).execute()
    except Exception as e:
        print(f"Failed to log alert message: {e}")

if __name__ == "__main__":
    print("Starting Ingestion Pipeline...")
    fetch_market_prices()
    fetch_weather_snapshots()
    run_calculations_and_rules()
    print("Ingestion Pipeline execution finished.")
