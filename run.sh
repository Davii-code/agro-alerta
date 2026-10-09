#!/usr/bin/env bash
# Roda o app injetando as credenciais do Supabase a partir do .env, que nunca
# vai para o git. main.dart le as duas via String.fromEnvironment; sem elas o
# app sobe em modo offline.
set -euo pipefail
cd "$(dirname "$0")"

export PATH="/home/davif/development/flutter/bin:$PATH"

[ -f .env ] || { echo "Falta o .env na raiz do projeto."; exit 1; }
set -a; . ./.env; set +a

exec flutter run "$@" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_KEY"
