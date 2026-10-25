#!/usr/bin/env bash
# Checks that a run of the two labs still shows what the article claims.
# usage: bash tests/check-results.sh LEAK_HUNT_OUTPUT ROTATION_OUTPUT
# Prints PASS or FAIL per claim and exits 1 if any claim fails. Connection
# counts aren't compared, because they vary by a few between machines.
set -uo pipefail

[ $# -eq 2 ] || { echo "usage: bash tests/check-results.sh LEAK_HUNT_OUTPUT ROTATION_OUTPUT"; exit 2; }
leak="$(tr -d '\r' < "$1")"
rotation="$(tr -d '\r' < "$2")"
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }
at_least() { awk -v t="$1" -v min="$2" 'BEGIN { exit !(t != "" && t + 0 >= min + 0) }'; }
more_than() { awk -v t="$1" -v min="$2" 'BEGIN { exit !(t != "" && t + 0 > min + 0) }'; }

# Lab 1: the scorecard, line for line ("label|verdict").
expected='git: files in the current commit|not found
git: history (git log -p)|FOUND
docker: ARG used in a RUN step|FOUND
docker: ARG promoted to ENV|FOUND
docker: COPY . . with no .dockerignore|FOUND
docker: COPY . . with .env in .dockerignore|not found
docker: RUN --mount=type=secret|not found
kubernetes: Secret manifest, after base64 -d|FOUND'
actual="$(printf '%s\n' "$leak" \
  | awk '/^== where did .* end up\?/ { on = 1; next } on && (NF == 0 || /^\(/) { exit } on' \
  | sed -E 's/[[:space:]]{2,}(FOUND|not found)$/|\1/')"
if [ "$actual" = "$expected" ]; then
  pass "leak hunt: the scorecard matches the article (5 of 8 places FOUND)"
else
  fail "leak hunt: the scorecard changed"
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/      /'
fi

# Lab 2: one block per mode, from "== <mode>" to the next "== ".
block() { printf '%s\n' "$rotation" | awk -v mode="$1" '/^== / { on = ($2 == mode) } on'; }
inplace="$(block in-place)"
twousers="$(block two-users)"

failed="$(printf '%s\n' "$inplace" | sed -nE 's/.*result: ([0-9]+) of [0-9]+ new connections failed.*/\1/p')"
if more_than "$failed" 0; then pass "rotation in-place: new connections failed ($failed)"
else fail "rotation in-place: expected some new connections to fail, got '${failed:-none}'"; fi

if printf '%s\n' "$inplace" | grep -q 'successful connections in that window: 0$'; then
  pass "rotation in-place: no new connection succeeded during the gap"
else fail "rotation in-place: a new connection succeeded during the gap, or the line is missing"; fi

t="$(printf '%s\n' "$inplace" | sed -nE 's/.*pool session \(app\) still answering at t=([0-9.]+)s.*/\1/p' | tail -n 1)"
if at_least "$t" 10; then pass "rotation in-place: the open connection kept answering to the end (t=${t}s)"
else fail "rotation in-place: the open connection stopped early (last answer t=${t:-none}s)"; fi

if printf '%s\n' "$twousers" | grep -qE 'result: 0 of [0-9]+ new connections failed'; then
  pass "rotation two-users: no new connection failed"
else fail "rotation two-users: some new connections failed, or the result line is missing"; fi

t="$(printf '%s\n' "$twousers" | sed -nE 's/.*pool session \(app_blue\) still answering at t=([0-9.]+)s.*/\1/p' | tail -n 1)"
if more_than "$t" 7; then pass "rotation two-users: the open connection kept answering after NOLOGIN (t=${t}s)"
else fail "rotation two-users: the open connection stopped by NOLOGIN (last answer t=${t:-none}s)"; fi

if printf '%s\n' "$twousers" | grep -q 'terminating connection due to administrator command'; then
  pass "rotation two-users: pg_terminate_backend() ended the open connection"
else fail "rotation two-users: the open connection was never ended"; fi

[ "$failures" -eq 0 ] || { echo "$failures claim(s) no longer hold"; exit 1; }
echo "all claims hold"
