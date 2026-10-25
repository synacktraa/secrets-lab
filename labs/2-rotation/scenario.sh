# scenario.sh (called by run.sh): runs inside a postgres:17-alpine container on the "rotlab"
# network, next to a Postgres server reachable as "db".
# usage: sh -s in-place | sh -s two-users
set -u
MODE="$1"
ADMIN="host=db user=postgres password=admin dbname=app"
until pg_isready -h db -q; do sleep 0.2; done

sql() { PGOPTIONS="-c client_min_messages=warning" psql "$ADMIN" -qtAX -v ON_ERROR_STOP=1 -c "$1"; }
use_creds() { printf 'DB_USER=%s\nDB_PASSWORD=%s\n' "$1" "$2" > /tmp/creds.new && mv /tmp/creds.new /tmp/creds; }
T0=$(cut -d' ' -f1 /proc/uptime)
now() { awk -v t0="$T0" '{printf "%.1f", $1 - t0}' /proc/uptime; }
say() { echo "  t=$(now)s  $*"; }
at() { while [ "$(awk -v t0="$T0" -v t="$1" '{print ($1 - t0 >= t)}' /proc/uptime)" = 0 ]; do sleep 0.05; done; }

# The fake app: a fresh connection every 100 ms, like a service that scales or restarts.
app() {
  while [ ! -f /tmp/stop ]; do
    . /tmp/creds
    if out=$(PGCONNECT_TIMEOUT=2 psql "host=db user=$DB_USER password=$DB_PASSWORD dbname=app" -qtAXc "select 1" 2>&1); then
      echo "ok $DB_USER $(now)" >> /tmp/app.log
    else
      echo "FAIL $DB_USER $(now) $(echo "$out" | head -n 1)" >> /tmp/app.log
    fi
    sleep 0.1
  done
}

# One long-lived connection, like a pooled connection that never reconnects.
pool() {
  . /tmp/creds
  while [ ! -f /tmp/stop ]; do
    echo "select 'pool session (' || current_user || ') still answering at t=$(now)s';"
    sleep 0.5
  done | psql "host=db user=$DB_USER password=$DB_PASSWORD dbname=app" -qtAX >> /tmp/pool.log 2>&1
}

sql "DROP ROLE IF EXISTS app; DROP ROLE IF EXISTS app_blue; DROP ROLE IF EXISTS app_green;"
if [ "$MODE" = in-place ]; then
  sql "CREATE ROLE app LOGIN PASSWORD 'pw-1'"
  use_creds app pw-1
else
  sql "CREATE ROLE app_blue LOGIN PASSWORD 'blue-pw'"
  use_creds app_blue blue-pw
fi

app & pool &
say "app and pool session running as $(. /tmp/creds; echo "$DB_USER")"

if [ "$MODE" = in-place ]; then
  at 3; sql "ALTER ROLE app PASSWORD 'pw-2'"; say "rotate: ALTER ROLE app PASSWORD (old password is dead now)"
  at 8; use_creds app pw-2;                   say "redeploy lands: app now uses the new password"
else
  at 3; sql "CREATE ROLE app_green LOGIN PASSWORD 'green-pw'"; say "issue: CREATE ROLE app_green (both logins work)"
  at 5; use_creds app_green green-pw;                          say "roll: app now connects as app_green"
  at 7; sql "ALTER ROLE app_blue NOLOGIN";                     say "revoke: ALTER ROLE app_blue NOLOGIN"
  at 9; sql "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE usename = 'app_blue'" > /dev/null
        say "revoke for real: pg_terminate_backend() on app_blue's sessions"
fi
at 11; touch /tmp/stop; wait

ok=$(grep -c '^ok' /tmp/app.log); failed=$(grep -c '^FAIL' /tmp/app.log)
echo "  result: $failed of $((ok + failed)) new connections failed"
if [ "$failed" -gt 0 ]; then
  first=$(grep '^FAIL' /tmp/app.log | head -n 1 | cut -d' ' -f3)
  last=$(grep '^FAIL' /tmp/app.log | tail -n 1 | cut -d' ' -f3)
  inside=$(awk -v a="$first" -v b="$last" '$1 == "ok" && $3 >= a && $3 <= b' /tmp/app.log | wc -l)
  echo "  failures from t=${first}s to t=${last}s; successful connections in that window: $inside"
  grep '^FAIL' /tmp/app.log | head -n 1 | cut -d' ' -f4- | sed 's/^/    /'
fi
echo "  pool session, last answer and how it ended:"
grep 'still answering' /tmp/pool.log | tail -n 1 | sed 's/^/    /'
grep -m 1 'FATAL' /tmp/pool.log | sed 's/^/    /'
