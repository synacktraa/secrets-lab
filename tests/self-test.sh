#!/usr/bin/env bash
# Proves tests/check-results.sh passes on the recorded lab runs and fails when
# any claim the article makes stops holding. Needs only bash: no Docker.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
LEAK="$ROOT/labs/1-leak-hunt/output.txt"
ROT="$ROOT/labs/2-rotation/output.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
status=0

# expect pass|fail DESCRIPTION LEAK_FILE ROTATION_FILE
expect() {
  if bash "$HERE/check-results.sh" "$3" "$4" > "$TMP/out" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$1" ]; then
    echo "ok     $2"
  else
    echo "WRONG  $2 (expected $1, got $got)"
    sed 's/^/       /' "$TMP/out"
    status=1
  fi
}

expect pass "the recorded runs" "$LEAK" "$ROT"

sed 's/^\(docker: RUN --mount=type=secret *\)not found/\1FOUND/' "$LEAK" > "$TMP/leak.txt"
expect fail "a secret mount that leaks" "$TMP/leak.txt" "$ROT"

sed '/== in-place/,/== two-users/ s/result: [0-9]* of/result: 0 of/' "$ROT" > "$TMP/rot1.txt"
expect fail "no failures when changing the password in place" "$LEAK" "$TMP/rot1.txt"

sed 's/successful connections in that window: 0/successful connections in that window: 3/' "$ROT" > "$TMP/rot2.txt"
expect fail "connections that succeed during the gap" "$LEAK" "$TMP/rot2.txt"

sed '/== in-place/,/== two-users/ s/still answering at t=[0-9.]*s/still answering at t=4.0s/' "$ROT" > "$TMP/rot3.txt"
expect fail "an open connection that stops at the password change" "$LEAK" "$TMP/rot3.txt"

sed '/== two-users/,$ s/result: 0 of/result: 4 of/' "$ROT" > "$TMP/rot4.txt"
expect fail "failures with two logins" "$LEAK" "$TMP/rot4.txt"

sed '/== two-users/,$ s/still answering at t=[0-9.]*s/still answering at t=6.0s/' "$ROT" > "$TMP/rot5.txt"
expect fail "an open connection that NOLOGIN stops" "$LEAK" "$TMP/rot5.txt"

sed '/terminating connection due to administrator command/d' "$ROT" > "$TMP/rot6.txt"
expect fail "an open connection that's never ended" "$LEAK" "$TMP/rot6.txt"

exit $status
