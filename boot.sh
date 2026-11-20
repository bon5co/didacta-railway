#!/bin/bash
# Didacta on Railway: put the web app on the injected PORT, then create the first organisation and administrator from variables
# once the API answers, and hand over to the stock entrypoint.
set -euo pipefail

need() { [ -n "${!1:-}" ] || { echo "[railway-boot] $1 is required" >&2; exit 1; }; }
for n in ADMIN_DATABASE_URL REDIS_URL AUTH_SECRET DIDACTA_SETUP_TOKEN ADMIN_EMAIL ADMIN_PASSWORD RAILWAY_PUBLIC_DOMAIN; do need "$n"; done
[ "${#ADMIN_PASSWORD}" -ge 12 ] || { echo "[railway-boot] ADMIN_PASSWORD must be at least 12 characters" >&2; exit 1; }

# Railway injects PORT=8080 and its healthcheck and edge dial it; the web app proxies /api, /healthz and /readyz to the API
export WEB_PORT="${PORT:-8080}"
export API_PORT="${API_PORT:-4000}"
export WEB_PUBLIC_URL="${WEB_PUBLIC_URL:-https://$RAILWAY_PUBLIC_DOMAIN}"
export WEB_PUBLIC_ALLOWED_HOSTS="${WEB_PUBLIC_ALLOWED_HOSTS:-$RAILWAY_PUBLIC_DOMAIN}"

# The instance is created through the public setup endpoint, which only works while there are no organisations (409 after).
# Runs beside the stock entrypoint, which migrates first and only then starts the API.
(
  API="http://127.0.0.1:$API_PORT"
  n=0
  until curl -fsS -o /dev/null "$API/healthz" 2>/dev/null; do
    n=$((n+1)); [ "$n" -le 400 ] || { echo "[railway-boot] API never answered, setup skipped" >&2; exit 0; }; sleep 3
  done
  if curl -fsS "$API/api/v1/setup/status" 2>/dev/null | grep -q '"initialized":true'; then
    echo "[railway-boot] instance already initialised"; exit 0
  fi
  body=$(printf '{"organization":{"name":"%s","slug":"%s","primaryHostname":"%s"},"admin":{"name":"Administrator","email":"%s","password":"%s"}}' \
    "${ORG_NAME:-Didacta}" "${ORG_SLUG:-didacta}" "$RAILWAY_PUBLIC_DOMAIN" "$ADMIN_EMAIL" "$ADMIN_PASSWORD")
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$API/api/v1/setup/init" -H 'content-type: application/json' \
    -H "x-setup-token: $DIDACTA_SETUP_TOKEN" -H "x-forwarded-host: $RAILWAY_PUBLIC_DOMAIN" --data "$body" || true)
  echo "[railway-boot] setup/init answered $code"
) &

# A deploy killed while `prisma migrate deploy` is running (the generate pipeline's volume attach and domain create each redeploy,
# and so does any OOM kill or restart) leaves a _prisma_migrations row that started and never finished, plus whatever objects the
# killed migration had already created ("type TenantStatus already exists"). Prisma then refuses every later boot (P3009 / P3018).
# Measured on Railway 2026-11-21: deleting only the unfinished row is not enough, the baseline migration is not atomic.
# If NO migration has ever finished, the database holds nothing but that partial baseline and no user data (the app has never
# started), so the public schema is reset and the stock entrypoint applies everything again. If some migrations did finish, a
# later one was killed: that is left alone, because dropping anything there could cost real data.
(
  url="${ADMIN_DATABASE_URL%%\?*}"
  q() { psql "$url" -v ON_ERROR_STOP=1 -tAc "$1" 2>&1; }
  for _ in $(seq 1 60); do
    if out=$(q "SELECT count(*) FILTER (WHERE finished_at IS NULL AND rolled_back_at IS NULL) || ' ' || count(*) FILTER (WHERE finished_at IS NOT NULL) FROM _prisma_migrations"); then
      set -- $out
      if [ "${1:-0}" -gt 0 ] && [ "${2:-0}" -eq 0 ]; then
        q "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO PUBLIC" >/dev/null \
          && echo "[railway-boot] first migration never finished: reset the empty public schema for a clean retry"
      elif [ "${1:-0}" -gt 0 ]; then
        echo "[railway-boot] a later migration was killed mid-run; not touching a database that holds finished migrations"
      fi
      break
    fi
    case "$out" in *'does not exist'*) break ;; esac
    sleep 2
  done
)

exec /sbin/tini -- /usr/local/bin/entrypoint.sh "$@"
