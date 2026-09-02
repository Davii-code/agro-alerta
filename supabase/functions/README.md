# Edge Functions

These are not deployed automatically. Copy them into your Supabase project when
you are ready.

## Layout

Two functions share one delivery module, so WhatsApp is talked to from exactly
one place.

```
supabase/functions/
├── _shared/whatsapp.ts   Delivery providers (Cloud API / CallMeBot / dry-run)
├── notify-hotspot/       Regional focus alert (RF06 + RN14)
└── notify-producer/      Individual alert when your own field crosses the NDE
```

### Prerequisites

Apply the migrations first — the function calls RPCs and columns that only exist
after them:

```bash
supabase db push
```

`02_fix_hotspots.sql` rewrites `get_regional_hotspots` and `get_users_in_radius`
with new signatures. `03_mip_and_pest_map.sql` adds the `hotspot_key`,
`channel`, `delivery_status` and `provider_response` columns on `alert_logs`
that the de-duplication and audit trail depend on.

### Deploy

```bash
supabase functions deploy notify-hotspot
supabase functions deploy notify-producer
```

### Environment variables

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform. You
only set the ones below.

| Variable | Required | Purpose |
|---|---|---|
| `WHATSAPP_PROVIDER` | no | `evolution`, `cloud`, `callmebot` or `dry-run` (default) |
| `CRON_SECRET` | yes | Shared secret that lets a scheduled job invoke the function |
| `ALLOWED_ORIGIN` | recommended | Restricts CORS; defaults to `*` |
| `EVOLUTION_API_URL` | for `evolution` | Base URL of your instance, no trailing slash |
| `EVOLUTION_INSTANCE` | for `evolution` | Instance name created via `/instance/create` |
| `EVOLUTION_API_KEY` | for `evolution` | `AUTHENTICATION_API_KEY` or the instance token |
| `EVOLUTION_API_VERSION` | no | `v2` (default) or `v1` — changes the request body shape |
| `EVOLUTION_SEND_DELAY_MS` | no | Pause between sends, default `1500` |
| `WHATSAPP_PHONE_NUMBER_ID` | for `cloud` | From the Meta app dashboard |
| `WHATSAPP_ACCESS_TOKEN` | for `cloud` | Meta access token |
| `WHATSAPP_TEMPLATE_NAME` | no | Defaults to `alerta_praga` |
| `WHATSAPP_TEMPLATE_LANG` | no | Defaults to `pt_BR` |
| `CALLMEBOT_KEYS` | for `callmebot` | JSON map of phone to apikey |

```bash
supabase secrets set \
  WHATSAPP_PROVIDER=evolution \
  EVOLUTION_API_URL=https://evolution.seudominio.com \
  EVOLUTION_INSTANCE=agro-alerta \
  EVOLUTION_API_KEY=sua-chave \
  CRON_SECRET=$(openssl rand -hex 24)
```

### Authorisation

The function runs with the service role and bypasses RLS, so it can read every
producer's phone number and message all of them. An unauthenticated endpoint
would be a spam cannon pointed at real people. Two callers are accepted:

1. A scheduled job sending `X-Cron-Secret: <CRON_SECRET>`.
2. A signed-in user whose `profiles.role` is `extensionist`, via
   `Authorization: Bearer <user jwt>`.

Everything else gets 401 or 403 before any query runs.

### Calling it

Dry run (formats and logs, sends nothing):

```bash
curl -X POST "https://<project>.supabase.co/functions/v1/notify-hotspot" \
  -H "x-cron-secret: $CRON_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"dry_run": true}'
```

Accepted body keys, all optional: `dry_run`, `radius_meters` (default 5000),
`notify_radius_meters` (default 20000), `min_observers` (default 2),
`window_days` (default 7).

### Scheduling

In the Supabase dashboard, under Database → Cron Jobs:

```sql
select cron.schedule(
  'notify-hotspot-6h',
  '0 */6 * * *',
  $$
  select net.http_post(
    url     := 'https://<project>.supabase.co/functions/v1/notify-hotspot',
    headers := '{"Content-Type":"application/json","x-cron-secret":"<CRON_SECRET>"}'::jsonb,
    body    := '{}'::jsonb
  );
  $$
);
```

## `notify-producer`

Individual alert (RN 11): a producer's own field crossed its NDE. Called by
`pipeline/ingestion_pipeline.py` after it recomputes risk scores, never by the app.

Unlike `notify-hotspot` it accepts only the cron secret - there is no interactive
caller, so `Authorization: Bearer` is not an accepted path.

```bash
curl -X POST "https://<project>.supabase.co/functions/v1/notify-producer" \
  -H "x-cron-secret: $CRON_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"profile_id":"<uuid>","pest":"Lagarta-do-cartucho","field_name":"Talhao Norte","count":14,"nde":8,"dry_run":true}'
```

For the pipeline to reach it, set in `pipeline/.env`:

```
SUPABASE_FUNCTIONS_URL=https://<project>.supabase.co/functions/v1
CRON_SECRET=<same value as the function secret>
```

## Configurando o WhatsApp

### Opção A — Evolution API (principal)

Open source, roda em um container, sem aprovação de template, envia texto livre.
Conecta lendo um QR code com um número de WhatsApp comum.

**1. Suba a instância.** `docker-compose.yml`:

```yaml
services:
  evolution-api:
    image: atendai/evolution-api:v2.1.1
    container_name: evolution-api
    restart: always
    ports:
      - "8080:8080"
    environment:
      - AUTHENTICATION_API_KEY=troque-esta-chave
      - DATABASE_ENABLED=true
      - DATABASE_PROVIDER=postgresql
      - DATABASE_CONNECTION_URI=postgresql://postgres:postgres@evolution-db:5432/evolution
      - CACHE_REDIS_ENABLED=false
      - CACHE_LOCAL_ENABLED=true
      - LOG_LEVEL=ERROR
    volumes:
      - evolution_instances:/evolution/instances
    depends_on:
      - evolution-db

  evolution-db:
    image: postgres:16-alpine
    container_name: evolution-db
    restart: always
    environment:
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=evolution
    volumes:
      - evolution_db:/var/lib/postgresql/data

volumes:
  evolution_instances:
  evolution_db:
```

```bash
docker compose up -d
```

**2. Crie a instância e leia o QR code.**

```bash
curl -X POST "http://localhost:8080/instance/create" \
  -H "apikey: troque-esta-chave" \
  -H "Content-Type: application/json" \
  -d '{"instanceName":"agro-alerta","integration":"WHATSAPP-BAILEYS","qrcode":true}'
```

A resposta traz o QR em base64. Abra `http://localhost:8080/manager` no navegador
para uma tela mais confortável, e leia o código no WhatsApp do celular em
**Aparelhos conectados → Conectar um aparelho**.

Confira que conectou:

```bash
curl "http://localhost:8080/instance/connectionState/agro-alerta" \
  -H "apikey: troque-esta-chave"
```

Deve responder `"state": "open"`.

**3. Exponha na internet.** As Edge Functions rodam na infraestrutura do Supabase
e **não enxergam `localhost`**. Coloque a instância num VPS com domínio e HTTPS,
ou, para testar rápido:

```bash
ngrok http 8080
```

Use a URL pública gerada em `EVOLUTION_API_URL`.

**4. Aponte as funções para ela.**

```bash
supabase secrets set \
  WHATSAPP_PROVIDER=evolution \
  EVOLUTION_API_URL=https://sua-url-publica \
  EVOLUTION_INSTANCE=agro-alerta \
  EVOLUTION_API_KEY=troque-esta-chave
```

**5. Teste sem enviar nada:**

```bash
curl -X POST "https://<project>.supabase.co/functions/v1/notify-hotspot" \
  -H "x-cron-secret: $CRON_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"dry_run": true}'
```

Confira o `details` da resposta, e só depois tire o `dry_run`.

#### O que você precisa saber sobre o risco

A Evolution API funciona pelo protocolo do **WhatsApp Web**, através de um número
comum que você vincula por QR code. Não é uma integração oficial: o WhatsApp pode
bloquear o número vinculado, e envio em massa não solicitado é o gatilho mais
comum para isso. Recomendações práticas:

- Use um chip dedicado, nunca o número pessoal ou o da empresa
- Deixe o `EVOLUTION_SEND_DELAY_MS` em 1500 ou mais — o código já espaça os envios
- A janela de cooldown de 24 h por produtor, já implementada, evita reenvio do
  mesmo foco e é a principal proteção contra parecer spam
- Aqueça o número por alguns dias antes de usar em volume

Se o número for bloqueado, a única mudança necessária é `WHATSAPP_PROVIDER=cloud`
mais as credenciais da Meta. O corpo da mensagem e o resto do fluxo não mudam.

#### Diferença entre v1 e v2

O corpo da requisição mudou entre as versões:

```jsonc
// v1
{ "number": "5562...", "options": { "delay": 1200 }, "textMessage": { "text": "..." } }
// v2
{ "number": "5562...", "delay": 1200, "text": "..." }
```

O código suporta as duas. Se sua instância for v1, defina `EVOLUTION_API_VERSION=v1`.

### Opção B — Meta WhatsApp Cloud API (oficial)

Gratuita e permanente no número de teste, sem cartão, mas entrega apenas para até
5 números verificados no painel e exige **template aprovado** — texto livre só é
permitido dentro de uma janela de 24 h de atendimento, que um alerta nunca tem.

1. Crie um app em <https://developers.facebook.com> e adicione o produto WhatsApp.
2. Copie o **Phone number ID** e o token da página API Setup. O token temporário
   expira em 24 h; para algo duradouro, crie um System User no Business Settings.
3. Cadastre cada destinatário em **To** → *Manage phone number list*.
4. Crie o template em **Message Templates**:
   - Nome: `alerta_praga`, categoria **Utility**, idioma `pt_BR`
   - Corpo:
     ```
     Ola, {{1}}! Um foco de {{2}} foi confirmado a {{3}} km do seu talhao {{4}}.
     Faca uma contagem hoje e registre no aplicativo Agro Alerta.
     ```
5. `supabase secrets set WHATSAPP_PROVIDER=cloud WHATSAPP_PHONE_NUMBER_ID=... WHATSAPP_ACCESS_TOKEN=...`

O template `hello_world` já vem pronto e serve para provar a ponta enquanto o
`alerta_praga` está em análise — aponte `WHATSAPP_TEMPLATE_NAME` para ele e
`WHATSAPP_TEMPLATE_LANG` para `en_US`.

### Opção C — CallMeBot (teste rápido)

Sem conta e sem template. Cada destinatário manda uma mensagem de ativação ao bot
e recebe uma apikey pessoal.

1. O destinatário adiciona **+34 621 331 709** aos contatos.
2. Envia: `I allow callmebot to send me messages`.
3. O bot responde com a apikey.

```bash
supabase secrets set WHATSAPP_PROVIDER=callmebot \
  CALLMEBOT_KEYS='{"5562999999999":"123456"}'
```

Serve para demonstração, não para produção: é um relay de terceiro, sem garantia
de entrega e sem identidade de remetente que você controle.
