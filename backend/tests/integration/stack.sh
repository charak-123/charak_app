#!/usr/bin/env bash
#
# Bring up a throwaway Supabase-compatible stack for the integration tests.
#
# Why this exists: tests/ mocks the Supabase client, so no SQL is ever executed
# there — constraints, RLS policies, triggers and column names are all unverified,
# and a query against a column that does not exist passes just as green as a
# correct one. (That is exactly how bookings.patient_address shipped missing.)
#
# What this is NOT: the Supabase CLI. That needs its own install and a heavier
# stack. Postgres + PostgREST + a path-rewriting gateway is enough to exercise the
# real client over real SQL, which is the part the mocks cannot reach. Auth,
# Storage and Realtime are absent — tests needing those stay in the mocked suite.
#
#   ./stack.sh up      start containers, apply every migration, print the env
#   ./stack.sh down    remove containers and network
#   ./stack.sh reset   drop and recreate the schema, migrations reapplied
#   ./stack.sh env     re-print the env without touching anything
#
# Then:  eval "$(./stack.sh env)" && python -m pytest tests/integration -q
set -euo pipefail

PG=charak-pgtest
REST=charak-postgrest
GW=charak-gw
NET=charak-test
GW_PORT=55480
JWT_SECRET="charak-test-jwt-secret-at-least-32-chars-long"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS="$HERE/../../../supabase/migrations"
PY="$HERE/../../.venv/bin/python"

mint_key() {
  "$PY" - <<PY
import jwt, time
print(jwt.encode({"role": "service_role", "iss": "supabase",
                  "iat": int(time.time()), "exp": int(time.time()) + 31536000},
                 "$JWT_SECRET", algorithm="HS256"))
PY
}

# Supabase ships these; a bare Postgres does not. RLS policies reference
# auth.uid(), and service_role must bypass RLS the way the backend's
# service-role client effectively does.
bootstrap_sql() {
  cat <<'SQL'
create schema if not exists auth;
create or replace function auth.uid() returns uuid
  language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create or replace function auth.role() returns text
  language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon') $$;
do $$ begin
  create role anon nologin;                     exception when duplicate_object then null; end $$;
do $$ begin
  create role authenticated nologin;            exception when duplicate_object then null; end $$;
do $$ begin
  create role service_role nologin bypassrls;   exception when duplicate_object then null; end $$;
SQL
}

grants_sql() {
  cat <<'SQL'
grant usage on schema public to anon, authenticated, service_role;
grant all privileges on all tables    in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant all privileges on all functions in schema public to service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all tables in schema public to anon;
SQL
}

psql_run() { docker exec -i "$PG" psql -U postgres -d charak -q -v ON_ERROR_STOP=1 "$@"; }

apply_migrations() {
  bootstrap_sql | psql_run
  for f in "$MIGRATIONS"/*.sql; do
    printf '  %s ... ' "$(basename "$f")"
    if docker cp "$f" "$PG:/tmp/m.sql" >/dev/null && psql_run -f /tmp/m.sql >/dev/null 2>&1; then
      echo ok
    else
      echo FAILED
      psql_run -f /tmp/m.sql 2>&1 | head -5
      exit 1
    fi
  done
  grants_sql | psql_run
  # PostgREST caches the schema; without this every new table 404s.
  docker kill -s SIGUSR1 "$REST" >/dev/null 2>&1 || true
}

print_env() {
  echo "export SUPABASE_URL=http://localhost:$GW_PORT"
  echo "export SUPABASE_SERVICE_ROLE_KEY=$(mint_key)"
  echo "export CHARAK_INTEGRATION=1"
}

case "${1:-up}" in
up)
  docker network create "$NET" >/dev/null 2>&1 || true
  docker rm -f "$PG" "$REST" "$GW" >/dev/null 2>&1 || true

  docker run -d --name "$PG" --network "$NET" \
    -e POSTGRES_PASSWORD=test -e POSTGRES_DB=charak postgres:16 >/dev/null
  printf 'waiting for postgres '
  for _ in $(seq 30); do
    docker exec "$PG" pg_isready -U postgres >/dev/null 2>&1 && break
    printf .; sleep 1
  done; echo

  docker run -d --name "$REST" --network "$NET" \
    -e PGRST_DB_URI="postgres://postgres:test@$PG:5432/charak" \
    -e PGRST_DB_SCHEMAS=public -e PGRST_DB_ANON_ROLE=anon \
    -e PGRST_JWT_SECRET="$JWT_SECRET" -e PGRST_DB_POOL=10 \
    postgrest/postgrest:v12.2.3 >/dev/null

  # supabase-py appends /rest/v1 to the project URL; real Supabase routes that to
  # PostgREST through Kong. Strip the prefix so the unmodified client works here.
  cfg=$(mktemp)
  cat > "$cfg" <<CONF
server {
  listen 8080;
  location /rest/v1/ { proxy_pass http://$REST:3000/; proxy_set_header Authorization \$http_authorization; }
  location / { return 404; }
}
CONF
  docker run -d --name "$GW" --network "$NET" -p "$GW_PORT:8080" \
    -v "$cfg:/etc/nginx/conf.d/default.conf:ro" nginx:alpine >/dev/null
  sleep 3

  echo "applying migrations:"
  apply_migrations
  echo
  echo "stack up. run:"
  echo "  eval \"\$(./stack.sh env)\" && python -m pytest tests/integration -q"
  echo
  print_env
  ;;
down)
  docker rm -f "$PG" "$REST" "$GW" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  echo "stack down."
  ;;
reset)
  psql_run -c 'drop schema public cascade; create schema public;' >/dev/null
  echo "schema dropped, reapplying:"
  apply_migrations
  echo "reset done."
  ;;
env) print_env ;;
*) echo "usage: $0 {up|down|reset|env}" >&2; exit 2 ;;
esac
