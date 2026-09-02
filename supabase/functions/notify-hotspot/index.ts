// notify-hotspot
//
// Finds pest focuses confirmed by two or more distinct observers within 5 km over
// the last 7 days (RF06), then messages every producer whose field of the affected
// crop lies within 20 km (RN 14).
//
// Runs with the service role, which bypasses RLS. That makes it a mass-notification
// endpoint, so it authenticates every caller before doing anything - see authorise().

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { AlertPayload, formatMessage, resolveProvider } from "../_shared/whatsapp.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const HOTSPOT_RADIUS_M = 5000;
const NOTIFY_RADIUS_M = 20000;
const MIN_OBSERVERS = 2;
const WINDOW_DAYS = 7;

/** A producer is not messaged about the same focus twice inside this window. */
const COOLDOWN_HOURS = 24;

interface Hotspot {
  cluster_id: number;
  pest_name: string;
  crop_type: string;
  observer_count: number;
  sampling_count: number;
  total_specimens: number;
  latitude: number;
  longitude: number;
  last_seen: string;
}

interface NearbyUser {
  profile_id: string;
  user_name: string;
  user_phone: string;
  field_name: string;
  crop_type: string;
  distance_meters: number;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

/**
 * Stable identifier for a focus: pest plus coordinates rounded to roughly 1 km.
 * Cluster ids are recomputed on every call and are not stable across runs, so
 * they cannot be used to recognise "the same focus as last time".
 */
function hotspotKey(h: Hotspot): string {
  const lat = h.latitude.toFixed(2);
  const lon = h.longitude.toFixed(2);
  return `${h.pest_name}@${lat},${lon}`;
}

/**
 * Authorises the caller. The function holds the service role key, so an open
 * endpoint would let anyone spam every registered producer's real phone number.
 *
 * Two accepted callers:
 *   - a scheduled job presenting X-Cron-Secret matching CRON_SECRET
 *   - a signed-in user whose profiles.role is extensionist
 */
async function authorise(
  req: Request,
  admin: SupabaseClient,
): Promise<
  { ok: true; actor: string } | { ok: false; status: number; error: string }
> {
  const cronSecret = Deno.env.get("CRON_SECRET");
  const presented = req.headers.get("x-cron-secret");
  if (cronSecret && presented && presented === cronSecret) {
    return { ok: true, actor: "cron" };
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) {
    return { ok: false, status: 401, error: "Autenticacao obrigatoria." };
  }

  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData?.user) {
    return { ok: false, status: 401, error: "Token invalido." };
  }

  const { data: profile } = await admin
    .from("profiles")
    .select("role, name")
    .eq("id", userData.user.id)
    .maybeSingle();

  if (!profile || profile.role !== "extensionist") {
    return {
      ok: false,
      status: 403,
      error: "Apenas extensionistas podem disparar alertas regionais.",
    };
  }

  return { ok: true, actor: `extensionist:${userData.user.id}` };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Use POST." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return json(
      { error: "Funcao nao configurada (URL ou service role ausente)." },
      500,
    );
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const auth = await authorise(req, admin);
  if (!auth.ok) return json({ error: auth.error }, auth.status);

  // Optional body. A missing or malformed body must not 400 a cron invocation,
  // so parse failures fall back to defaults instead of throwing.
  let options: Record<string, unknown> = {};
  try {
    const raw = await req.text();
    if (raw.trim().length > 0) options = JSON.parse(raw);
  } catch {
    options = {};
  }

  const dryRun = options.dry_run === true;
  const radiusMeters = Number(options.radius_meters ?? HOTSPOT_RADIUS_M);
  const notifyRadius = Number(options.notify_radius_meters ?? NOTIFY_RADIUS_M);
  const minObservers = Number(options.min_observers ?? MIN_OBSERVERS);
  const windowDays = Number(options.window_days ?? WINDOW_DAYS);

  try {
    const { data: hotspots, error: hotspotError } = await admin.rpc(
      "get_regional_hotspots",
      {
        radius_meters: radiusMeters,
        min_observers: minObservers,
        window_days: windowDays,
      },
    );

    if (hotspotError) throw hotspotError;

    const focuses = (hotspots ?? []) as Hotspot[];
    if (focuses.length === 0) {
      return json({
        success: true,
        hotspots: 0,
        notified: 0,
        message: "Nenhum foco confirmado no periodo.",
      });
    }

    const provider = resolveProvider();
    const cutoff = new Date(Date.now() - COOLDOWN_HOURS * 3600_000)
      .toISOString();

    let notified = 0;
    let skipped = 0;
    let failed = 0;
    const perHotspot: unknown[] = [];

    // Every focus is processed, not only the first one.
    for (const hotspot of focuses) {
      const key = hotspotKey(hotspot);

      // Which crops this pest threatens. Lagarta-do-cartucho hits maize, soybean
      // AND cotton, so notifying only the cluster's dominant crop would leave
      // most of the exposed producers out. An unmapped pest falls back to the
      // cluster's own crop, and finally to "every crop".
      const { data: cropRows } = await admin
        .from("pest_crop_map")
        .select("culture")
        .eq("pest_species", hotspot.pest_name);

      const crops: (string | null)[] = (cropRows ?? []).length > 0
        ? (cropRows as { culture: string }[]).map((r) => r.culture)
        : [hotspot.crop_type ?? null];

      const users: NearbyUser[] = [];
      for (const crop of crops) {
        const { data: nearby, error: nearbyError } = await admin.rpc(
          "get_users_in_radius",
          {
            p_lat: hotspot.latitude,
            p_lon: hotspot.longitude,
            radius_meters: notifyRadius,
            p_culture: crop,
          },
        );

        if (nearbyError) throw nearbyError;
        users.push(...((nearby ?? []) as NearbyUser[]));
      }

      // One row per producer: the RPC returns one row per field, and a producer
      // with three fields should still get a single message (their closest one).
      const closestByProducer = new Map<string, NearbyUser>();
      for (const u of users) {
        const existing = closestByProducer.get(u.profile_id);
        if (!existing || u.distance_meters < existing.distance_meters) {
          closestByProducer.set(u.profile_id, u);
        }
      }

      const recipients: unknown[] = [];

      for (const user of closestByProducer.values()) {
        // De-duplication: skip anyone already alerted about this focus inside
        // the cooldown. Without it every invocation re-messages everybody.
        const { data: recent } = await admin
          .from("alert_logs")
          .select("id")
          .eq("profile_id", user.profile_id)
          .eq("hotspot_key", key)
          .gte("sent_at", cutoff)
          .limit(1);

        if (recent && recent.length > 0) {
          skipped++;
          recipients.push({
            profile_id: user.profile_id,
            status: "skipped_cooldown",
          });
          continue;
        }

        const payload: AlertPayload = {
          toPhone: user.user_phone ?? "",
          producerName: user.user_name ?? "Produtor",
          pestName: hotspot.pest_name,
          fieldName: user.field_name ?? "seu talhao",
          distanceKm: (user.distance_meters / 1000).toFixed(1),
        };

        const result = dryRun
          ? { ok: true, detail: "dry_run solicitado na chamada" }
          : await provider.send(payload);

        if (result.ok) notified++;
        else failed++;

        // Logged whether or not delivery succeeded: alert_logs is the audit
        // trail and the source of truth for the cooldown above.
        await admin.from("alert_logs").insert({
          profile_id: user.profile_id,
          pest_species: hotspot.pest_name,
          severity: "vermelho",
          message: formatMessage(payload),
          hotspot_key: key,
          channel: provider.name,
          delivery_status: result.ok ? "sent" : "failed",
          provider_response: result.detail.slice(0, 1000),
        });

        recipients.push({
          profile_id: user.profile_id,
          distance_km: payload.distanceKm,
          status: result.ok ? "sent" : "failed",
          detail: result.ok ? undefined : result.detail,
        });
      }

      perHotspot.push({
        pest: hotspot.pest_name,
        crop: hotspot.crop_type,
        observers: hotspot.observer_count,
        latitude: hotspot.latitude,
        longitude: hotspot.longitude,
        hotspot_key: key,
        recipients,
      });
    }

    return json({
      success: true,
      actor: auth.actor,
      provider: provider.name,
      dry_run: dryRun,
      hotspots: focuses.length,
      notified,
      skipped_cooldown: skipped,
      failed,
      details: perHotspot,
    });
  } catch (error) {
    // `error` is `unknown` under Deno's strict TypeScript; narrow before use.
    const detail = error instanceof Error ? error.message : String(error);
    console.error("notify-hotspot:", detail);
    // A failure here is server-side, not a malformed request.
    return json({ error: detail }, 500);
  }
});
