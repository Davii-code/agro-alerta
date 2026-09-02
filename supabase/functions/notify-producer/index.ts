// notify-producer
//
// Sends the individual alert: the producer's OWN field crossed the economic
// threshold (RN 11). This is the counterpart to notify-hotspot, which handles
// the regional case (a focus confirmed by several neighbours).
//
// It exists so that WhatsApp delivery lives in exactly one place. The Python
// pipeline calls this instead of formatting and printing its own message.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { AlertPayload, normalisePhone, resolveProvider } from "../_shared/whatsapp.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** Same field is not re-alerted inside this window. */
const COOLDOWN_HOURS = 24;

interface RequestBody {
  profile_id?: string;
  phone?: string;
  name?: string;
  pest?: string;
  field_name?: string;
  field_id?: string;
  count?: number;
  nde?: number;
  dry_run?: boolean;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

/** Wording for the individual case: this is your field, not your region. */
function ownFieldMessage(b: RequestBody): string {
  return [
    "*AGRO ALERTA GO*",
    "",
    `Ola, ${b.name ?? "Produtor"}!`,
    `A contagem de *${b.pest}* no seu talhao *${b.field_name}* chegou a *${b.count}*,`,
    `acima do ponto de prejuizo calculado (${Math.round(b.nde ?? 0)}).`,
    "",
    "*Recomendacao:* a aplicacao ja se paga. Fale com seu extensionista.",
  ].join("\n");
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  // Only the pipeline calls this, and it holds CRON_SECRET. Unlike
  // notify-hotspot there is no interactive caller, so the secret is mandatory
  // rather than one of two accepted paths.
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (!cronSecret || req.headers.get("x-cron-secret") !== cronSecret) {
    return json({ error: "Nao autorizado." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "Funcao nao configurada." }, 500);
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Corpo JSON invalido." }, 400);
  }

  if (!body.profile_id || !body.pest) {
    return json({ error: "profile_id e pest sao obrigatorios." }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  try {
    // Phone from the request is only a hint; profiles is authoritative.
    const { data: profile } = await admin
      .from("profiles")
      .select("name, phone")
      .eq("id", body.profile_id)
      .maybeSingle();

    const phone = normalisePhone(profile?.phone ?? body.phone ?? "");
    if (!phone) {
      return json({ error: "Produtor sem telefone cadastrado." }, 422);
    }

    const key = `field:${body.field_id ?? body.field_name ?? "?"}:${body.pest}`;
    const cutoff = new Date(Date.now() - COOLDOWN_HOURS * 3600_000)
      .toISOString();

    const { data: recent } = await admin
      .from("alert_logs")
      .select("id")
      .eq("profile_id", body.profile_id)
      .eq("hotspot_key", key)
      .gte("sent_at", cutoff)
      .limit(1);

    if (recent && recent.length > 0) {
      return json({ success: true, status: "skipped_cooldown", hotspot_key: key });
    }

    const provider = resolveProvider();
    const message = ownFieldMessage(body);

    const payload: AlertPayload = {
      toPhone: phone,
      producerName: profile?.name ?? body.name ?? "Produtor",
      pestName: body.pest,
      fieldName: body.field_name ?? "seu talhao",
      // Reused by the Cloud API template as {{3}}; for the individual alert the
      // "distance" slot carries the observed count instead.
      distanceKm: String(body.count ?? 0),
      // Providers that send free-form text (Evolution, CallMeBot) use this
      // instead of the regional wording that formatMessage would otherwise build.
      body: message,
    };
    const result = body.dry_run
      ? { ok: true, detail: "dry_run solicitado na chamada" }
      : await provider.send(payload);

    await admin.from("alert_logs").insert({
      profile_id: body.profile_id,
      pest_species: body.pest,
      severity: "vermelho",
      message,
      hotspot_key: key,
      channel: provider.name,
      delivery_status: result.ok ? "sent" : "failed",
      provider_response: result.detail.slice(0, 1000),
    });

    return json({
      success: result.ok,
      provider: provider.name,
      hotspot_key: key,
      detail: result.detail,
    }, result.ok ? 200 : 502);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    console.error("notify-producer:", detail);
    return json({ error: detail }, 500);
  }
});
