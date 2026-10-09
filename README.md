# Agro Alerta GO

Monitoramento integrado de pragas (MIP) para produtores de Goiás. O produtor
conta pragas na lavoura **sem internet**, o aplicativo calcula se a aplicação já
se paga, e quando vizinhos confirmam o mesmo foco todo mundo da região recebe um
alerta no WhatsApp.

## Arquitetura

| Camada | O que faz |
|---|---|
| **Flutter** | App offline-first. Toda escrita vai primeiro para o Hive local. |
| **Supabase** | Postgres + PostGIS + Auth + RLS. Fonte da verdade quando há rede. |
| **Edge Functions** | Deno. Confirmam focos regionais e enviam o WhatsApp. |
| **Pipeline Python** | Batch: preços CONAB, clima NASA Power, recálculo de risco. |

Uma amostragem nunca espera a rede: `_saveSampling` grava no Hive com
`isSynced: false` e retorna. O `SyncService` empurra depois, em lote, disparado
tanto por um timer de 30 s quanto pelo retorno da conexão.

## Rodando o app

Credenciais **não ficam no código**. São injetadas no build:

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=SUA_ANON_KEY
```

Sem `--dart-define` o app sobe em modo offline: em build de debug aceita
qualquer login para demonstração; em release recusa entrar, porque um usuário
sem UUID real não consegue sincronizar (a RLS exige `auth.uid() = observer_id`).

### Google Maps no Android

A chave vai em `android/local.properties` (que já está no `.gitignore`):

```properties
googleMaps.apiKey=AIza...
```

O `build.gradle.kts` injeta esse valor no manifesto. Sem a chave o app compila
normalmente e o radar usa o mapa vetorial simplificado.

### Permissões

`AndroidManifest.xml` declara `INTERNET`, `ACCESS_FINE_LOCATION` e
`ACCESS_COARSE_LOCATION`. O `Info.plist` do iOS declara
`NSLocationWhenInUseUsageDescription`. Sem elas o GPS falha e toda amostragem
grava a mesma coordenada, o que quebra o agrupamento regional (RF06).

## Banco de dados

```bash
supabase db push
```

| Migration | O que traz |
|---|---|
| `01_schema.sql` | Tabelas, RLS, trigger `handle_new_user`, índices GiST |
| `02_fix_hotspots.sql` | `get_regional_hotspots` com `ST_ClusterDBSCAN`; `get_users_in_radius` por lat/lon |
| `03_mip_and_pest_map.sql` | `mip_parameters` por cultura **e** praga, `pest_crop_map`, colunas de deduplicação em `alert_logs` |

## Edge Functions

O envio de WhatsApp usa a **Evolution API** (open source, roda em Docker, conecta
por QR code, sem aprovação de template). Meta Cloud API e CallMeBot ficam como
alternativas selecionáveis por variável de ambiente.

Ver [`supabase/functions/README.md`](supabase/functions/README.md) para o
docker-compose, o deploy e as variáveis.

As funções **não são publicadas automaticamente** — ficam versionadas aqui para
você aplicar no Supabase quando quiser.

## Pipeline

```bash
cd pipeline
pip install -r requirements.txt
cp .env.example .env   # preencha
python ingestion_pipeline.py
```

### Execução automática (GitHub Actions)

`.github/workflows/supabase-keepalive.yml` roda todos os dias às 11:17 UTC
(08:17 em Brasília) e também pode ser disparado à mão em Actions →
*Supabase keepalive* → *Run workflow*. O job `heartbeat` grava uma linha em
`public.keepalive`; o job `ingestion` executa `pipeline/ingestion_pipeline.py`
em seguida. A escrita diária é o que impede o Supabase de pausar o projeto por
inatividade no plano free.

Secrets necessários em *Settings → Secrets and variables → Actions*:

| Secret | Obrigatório | Para quê |
|---|---|---|
| `SUPABASE_URL` | sim | `https://<ref>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | sim | escreve ignorando RLS |
| `SUPABASE_FUNCTIONS_URL` | não | alertas regionais via Edge Function |
| `CRON_SECRET` | não | mesmo valor do segredo da Edge Function |

Sem os dois primeiros o workflow falha de propósito, em vez de passar sem
escrever nada. Aplique a migration `04_keepalive.sql` antes do primeiro run.

## Requisitos implementados

| Requisito | Onde |
|---|---|
| Autenticação | [`auth_service.dart`](lib/services/auth_service.dart) |
| RF01 — registro offline | [`new_sampling_screen.dart`](lib/screens/new_sampling_screen.dart) |
| RF02 — sync em lote | [`sync_service.dart`](lib/services/sync_service.dart) |
| RF03 — score de risco | [`risk_calculator.dart`](lib/services/risk_calculator.dart) |
| RF04 — NDE | [`risk_calculator.dart`](lib/services/risk_calculator.dart) + [`mip_service.dart`](lib/services/mip_service.dart) |
| RF05 — radar colaborativo | [`radar_screen.dart`](lib/screens/radar_screen.dart) |
| RF06 — validação regional | [`02_fix_hotspots.sql`](supabase/migrations/02_fix_hotspots.sql) |
| Alerta WhatsApp | [`supabase/functions/`](supabase/functions/) |

## Fórmula do NDE

```
NDE = (C × K) / (V × I)
```

- **C** — custo de controle por hectare (R$), de `mip_parameters`
- **K** — eficácia esperada do controle (0 a 1)
- **V** — preço da saca (R$), de `market_prices`
- **I** — coeficiente de dano, por cultura **e** praga

Contagem acima do NDE significa que a aplicação se paga. Faixas: verde abaixo de
40, amarelo de 40 a 69, vermelho a partir de 70 — os mesmos cortes em
`risk_calculator.dart` e em `ingestion_pipeline.py`.
