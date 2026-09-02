// WhatsApp delivery providers.
//
// Implementations sit behind one interface so the choice of provider is an
// environment variable, not a code change:
//
//   WHATSAPP_PROVIDER=evolution  Evolution API, self-hosted (default choice)
//   WHATSAPP_PROVIDER=cloud      Meta WhatsApp Cloud API (official, template-only)
//   WHATSAPP_PROVIDER=callmebot  CallMeBot (zero-setup, one apikey per recipient)
//   WHATSAPP_PROVIDER=dry-run    Formats and logs, sends nothing (fallback)
//
// Evolution API is the primary target: it is open source, runs in one Docker
// container, needs no template approval, and sends free-form text - which is why
// the message body below is used verbatim rather than split into template slots.
//
// Trade-off worth knowing: Evolution API drives the WhatsApp *Web* protocol
// through a linked phone number. It is not an official WhatsApp integration, so
// the linked number can be blocked by WhatsApp, especially when it sends bulk
// unsolicited messages. That risk is on the number you link. The Cloud API path
// stays available for anyone who needs the officially sanctioned route.

export interface AlertPayload {
  toPhone: string;
  producerName: string;
  pestName: string;
  fieldName: string;
  distanceKm: string;

  /// Overrides the default regional wording. notify-producer sets this, because
  /// "a focus 3 km away" and "your own field crossed the threshold" are two
  /// different messages. Providers that send free-form text use it verbatim;
  /// the Cloud API ignores it and fills its template slots from the fields above.
  body?: string;
}

export interface SendResult {
  ok: boolean;
  detail: string;
}

export interface WhatsAppProvider {
  readonly name: string;
  send(payload: AlertPayload): Promise<SendResult>;
}

/** The message body. Sent verbatim by Evolution, CallMeBot and dry-run; mirrored
 *  by the Cloud API template variables so every channel reads the same. */
export function formatMessage(p: AlertPayload): string {
  if (p.body != null && p.body.trim().length > 0) return p.body;

  return [
    "*AGRO ALERTA GO*",
    "",
    `Ola, ${p.producerName}!`,
    `Um foco de *${p.pestName}* foi confirmado a ${p.distanceKm} km do seu talhao *${p.fieldName}*.`,
    "",
    "Foi confirmado por pelo menos 2 produtores diferentes nos ultimos 7 dias.",
    "Recomendacao: faca uma contagem no seu talhao ainda hoje e registre no aplicativo.",
  ].join("\n");
}

/** Digits only, with Brazil's country code, as every provider here expects. */
export function normalisePhone(raw: string): string {
  const digits = raw.replace(/\D/g, "");
  if (digits.length === 0) return "";
  if (digits.startsWith("55")) return digits;
  return `55${digits}`;
}

// ---------------------------------------------------------------------------
// Evolution API - self-hosted, open source, free-form text
// ---------------------------------------------------------------------------

class EvolutionApiProvider implements WhatsAppProvider {
  readonly name = "evolution";

  constructor(
    /** Base URL of the instance, e.g. https://evolution.seudominio.com */
    private baseUrl: string,
    /** The instance name created via /instance/create */
    private instance: string,
    /** AUTHENTICATION_API_KEY (global) or the instance token */
    private apiKey: string,
    /** Request body shape. v2 is current; v1 nested the text one level deeper. */
    private apiVersion: "v1" | "v2",
    /** Milliseconds to wait between sends, to look less like a burst. */
    private delayMs: number,
  ) {}

  async send(p: AlertPayload): Promise<SendResult> {
    const number = normalisePhone(p.toPhone);
    if (!number) return { ok: false, detail: "telefone vazio ou invalido" };

    const url = `${this.baseUrl}/message/sendText/${this.instance}`;
    const text = formatMessage(p);

    // v1 wrapped the content in textMessage; v2 flattened it. Supporting both
    // means an instance upgrade does not silently stop delivering.
    const body = this.apiVersion === "v1"
      ? { number, options: { delay: 1200, presence: "composing" }, textMessage: { text } }
      : { number, delay: 1200, text };

    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          "apikey": this.apiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });

      const detail = (await res.text()).slice(0, 500);

      if (!res.ok) {
        // 401 here almost always means the apikey is wrong; 404 means the
        // instance name does not exist or is not connected.
        return { ok: false, detail: `HTTP ${res.status}: ${detail}` };
      }

      // Pace the sends. Evolution will happily fire as fast as it is called, and
      // a burst from one linked number is what gets that number blocked.
      if (this.delayMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, this.delayMs));
      }

      return { ok: true, detail };
    } catch (err) {
      return {
        ok: false,
        detail: err instanceof Error ? err.message : String(err),
      };
    }
  }
}

// ---------------------------------------------------------------------------
// Meta WhatsApp Cloud API - official, requires an approved template
// ---------------------------------------------------------------------------

class CloudApiProvider implements WhatsAppProvider {
  readonly name = "cloud";

  constructor(
    private phoneNumberId: string,
    private accessToken: string,
    private templateName: string,
    private templateLanguage: string,
  ) {}

  async send(p: AlertPayload): Promise<SendResult> {
    const to = normalisePhone(p.toPhone);
    if (!to) return { ok: false, detail: "telefone vazio ou invalido" };

    const url = `https://graph.facebook.com/v21.0/${this.phoneNumberId}/messages`;

    // Business-initiated messages require an approved template. The variables
    // map positionally to {{1}}..{{4}} in the template body.
    const body = {
      messaging_product: "whatsapp",
      to,
      type: "template",
      template: {
        name: this.templateName,
        language: { code: this.templateLanguage },
        components: [
          {
            type: "body",
            parameters: [
              { type: "text", text: p.producerName },
              { type: "text", text: p.pestName },
              { type: "text", text: p.distanceKm },
              { type: "text", text: p.fieldName },
            ],
          },
        ],
      },
    };

    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${this.accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });

      const text = await res.text();
      if (!res.ok) return { ok: false, detail: `HTTP ${res.status}: ${text}` };
      return { ok: true, detail: text.slice(0, 500) };
    } catch (err) {
      return {
        ok: false,
        detail: err instanceof Error ? err.message : String(err),
      };
    }
  }
}

// ---------------------------------------------------------------------------
// CallMeBot - free, no account, recipient opts in by messaging the bot once
// ---------------------------------------------------------------------------

class CallMeBotProvider implements WhatsAppProvider {
  readonly name = "callmebot";

  // CallMeBot issues one apikey per recipient. Configure as a JSON object:
  //   CALLMEBOT_KEYS={"5562999999999":"123456","5562988888888":"654321"}
  constructor(private keys: Record<string, string>) {}

  async send(p: AlertPayload): Promise<SendResult> {
    const to = normalisePhone(p.toPhone);
    const apiKey = this.keys[to];
    if (!apiKey) {
      return { ok: false, detail: `sem apikey CallMeBot cadastrada para ${to}` };
    }

    const url = new URL("https://api.callmebot.com/whatsapp.php");
    url.searchParams.set("phone", `+${to}`);
    url.searchParams.set("text", formatMessage(p));
    url.searchParams.set("apikey", apiKey);

    try {
      const res = await fetch(url.toString());
      const text = await res.text();
      if (!res.ok) return { ok: false, detail: `HTTP ${res.status}: ${text}` };
      return { ok: true, detail: text.slice(0, 500) };
    } catch (err) {
      return {
        ok: false,
        detail: err instanceof Error ? err.message : String(err),
      };
    }
  }
}

// ---------------------------------------------------------------------------
// Dry run - the default when nothing is configured
// ---------------------------------------------------------------------------

class DryRunProvider implements WhatsAppProvider {
  readonly name = "dry-run";

  send(p: AlertPayload): Promise<SendResult> {
    const message = formatMessage(p);
    console.log(`[dry-run] -> ${normalisePhone(p.toPhone)}\n${message}`);
    return Promise.resolve({ ok: true, detail: "dry-run: nada enviado" });
  }
}

/** Picks the provider from the environment, degrading to dry-run when the chosen
 *  one is not fully configured. Never throws: a misconfigured provider must not
 *  take the whole function down, and a silent dry-run is safer than a crash. */
export function resolveProvider(): WhatsAppProvider {
  const choice = (Deno.env.get("WHATSAPP_PROVIDER") ?? "dry-run").toLowerCase();

  if (choice === "evolution") {
    const baseUrl = (Deno.env.get("EVOLUTION_API_URL") ?? "").replace(/\/+$/, "");
    const instance = Deno.env.get("EVOLUTION_INSTANCE") ?? "";
    const apiKey = Deno.env.get("EVOLUTION_API_KEY") ?? "";
    const apiVersion =
      (Deno.env.get("EVOLUTION_API_VERSION") ?? "v2") === "v1" ? "v1" : "v2";
    const delayMs = Number(Deno.env.get("EVOLUTION_SEND_DELAY_MS") ?? "1500");

    if (!baseUrl || !instance || !apiKey) {
      console.warn(
        "WHATSAPP_PROVIDER=evolution sem EVOLUTION_API_URL/INSTANCE/API_KEY; usando dry-run.",
      );
      return new DryRunProvider();
    }
    return new EvolutionApiProvider(
      baseUrl,
      instance,
      apiKey,
      apiVersion,
      Number.isFinite(delayMs) ? delayMs : 1500,
    );
  }

  if (choice === "cloud") {
    const phoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID") ?? "";
    const accessToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
    const template = Deno.env.get("WHATSAPP_TEMPLATE_NAME") ?? "alerta_praga";
    const language = Deno.env.get("WHATSAPP_TEMPLATE_LANG") ?? "pt_BR";

    if (!phoneNumberId || !accessToken) {
      console.warn("WHATSAPP_PROVIDER=cloud sem credenciais; usando dry-run.");
      return new DryRunProvider();
    }
    return new CloudApiProvider(phoneNumberId, accessToken, template, language);
  }

  if (choice === "callmebot") {
    try {
      const keys = JSON.parse(Deno.env.get("CALLMEBOT_KEYS") ?? "{}");
      return new CallMeBotProvider(keys);
    } catch {
      console.warn("CALLMEBOT_KEYS nao e um JSON valido; usando dry-run.");
      return new DryRunProvider();
    }
  }

  return new DryRunProvider();
}
