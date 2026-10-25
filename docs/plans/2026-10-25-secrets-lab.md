# Secrets lab Implementation Plan

**Goal:** Publish the two secrets experiments as a public repo that readers can run in Codespaces, see run in GitHub Actions, or run locally.
**Architecture:** The labs are bash scripts that drive Docker. A bash checker compares their output with the article's claims, and a self-test proves the checker can fail. GitHub Actions runs the self-test, both labs and the checker; a dev container gives Codespaces the same tools.
**Tech Stack:** bash, Docker (BuildKit), kubectl (client only), Python 3, GitHub Actions, Dev Containers.

Source of the labs: the earlier private copy of the labs (its README, `1-leak-hunt/` and `2-rotation/`; not `work/`). The commands below call it `$SRC`.
Repo: this folder (already `git init`, branch `main`, `core.autocrlf=false`). Run every command from its root.

---

### Task 1: Bring the labs over

**Files:**
- Create: `labs/` (copied), `.gitattributes`, `.gitignore`

- [ ] **Step 1: Copy the labs, without the scratch folder**

```bash
SRC=/path/to/the/earlier/lab
DST=labs
mkdir -p "$DST"
cp -r "$SRC/README.md" "$SRC/1-leak-hunt" "$SRC/2-rotation" "$DST/"
rm -rf "$DST/1-leak-hunt/work"
```

- [ ] **Step 2: Root `.gitattributes`**

```gitattributes
# Keep the scripts LF on Windows checkouts, where core.autocrlf=true would make
# them CRLF: labs/2-rotation/run.sh feeds scenario.sh to the postgres
# container's sh, which then fails, and bash on Linux fails on all of them.
*.sh text eol=lf
```

- [ ] **Step 3: Root `.gitignore`**

```gitignore
# scratch folder the leak hunt recreates on every run
work/
# lab outputs captured by CI or by hand at the repo root
/leak-hunt.txt
/rotation.txt
```

- [ ] **Step 4: Verify the copy matches the source**

Run: `diff -r --exclude=work --exclude=.gitattributes --exclude=.gitignore "$SRC" labs`
Expected: no output.

- [ ] **Step 5: Commit**

`git add -A && git commit -m "feat: the leak hunt and password rotation labs"`

---

### Task 2: The checker, test first

**Files:**
- Create: `tests/self-test.sh`, `tests/check-results.sh`

- [ ] **Step 1: Write the failing test, `tests/self-test.sh`**

```bash
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
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash tests/self-test.sh`
Expected: exit 1, with `WRONG  the recorded runs (expected pass, got fail)` because `check-results.sh` doesn't exist yet.

- [ ] **Step 3: Write `tests/check-results.sh`**

```bash
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
```

- [ ] **Step 4: Run the self-test and watch it pass**

Run: `bash tests/self-test.sh`
Expected: eight `ok` lines (the recorded runs, plus one broken copy per claim), exit 0.

- [ ] **Step 5: Commit**

`git add tests && git commit -m "test: check that lab runs still match the article"`

---

### Task 3: Both labs from the new paths

- [ ] **Step 1: Run both labs and the checker**

```bash
bash labs/1-leak-hunt/run.sh > leak-hunt.txt 2>&1
bash labs/2-rotation/run.sh > rotation.txt 2>&1
bash tests/check-results.sh leak-hunt.txt rotation.txt
```
Expected: seven `PASS` lines and `all claims hold`. (`leak-hunt.txt` and `rotation.txt` are ignored by git.)

---

### Task 4: GitHub Actions

**Files:**
- Create: `.github/workflows/tests.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: labs

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:
  schedule:
    - cron: "0 6 * * 1" # Mondays 06:00 UTC: catches image updates that break a lab

permissions:
  contents: read

defaults:
  run:
    shell: bash # runs with -eo pipefail, so tee can't hide a failing lab

jobs:
  labs:
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v7
      - name: The checker catches broken results
        run: bash tests/self-test.sh
      - name: "Lab 1: leak hunt"
        run: bash labs/1-leak-hunt/run.sh | tee leak-hunt.txt
      - name: "Lab 2: password rotation"
        run: bash labs/2-rotation/run.sh | tee rotation.txt
      - name: Results match the article
        run: bash tests/check-results.sh leak-hunt.txt rotation.txt
      - name: Keep the outputs
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: lab-outputs
          path: |
            leak-hunt.txt
            rotation.txt
          if-no-files-found: ignore
```

- [ ] **Step 2: Check it parses**

Run: `python -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/tests.yml')); print(list(d['jobs']['labs']['steps'][i].get('name', d['jobs']['labs']['steps'][i].get('uses')) for i in range(6)))"`
Expected: the six step names, no error.

- [ ] **Step 3: Commit**

`git add .github && git commit -m "ci: run the self-test and both labs on push, PRs, Mondays and on demand"`

---

### Task 5: Codespaces

**Files:**
- Create: `.devcontainer/devcontainer.json`, `.devcontainer/post-create.sh`

- [ ] **Step 1: `.devcontainer/devcontainer.json`**

```json
{
  "name": "secrets-lab",
  "image": "mcr.microsoft.com/devcontainers/python:3.12",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:4": {},
    "ghcr.io/devcontainers/features/kubectl-helm-minikube:1": { "helm": "none", "minikube": "none" }
  },
  "postCreateCommand": "bash .devcontainer/post-create.sh",
  "customizations": {
    "codespaces": { "openFiles": ["README.md"] }
  }
}
```

- [ ] **Step 2: `.devcontainer/post-create.sh`**

```bash
#!/usr/bin/env bash
# Runs once when the codespace is created: waits for Docker to start, then
# downloads the two images the labs use, so the first run doesn't wait on them.
set -euo pipefail
for _ in $(seq 60); do docker info > /dev/null 2>&1 && break; sleep 1; done
docker pull -q python:3.12-slim
docker pull -q postgres:17-alpine
```

- [ ] **Step 3: Check the JSON and the script parse**

Run: `python -c "import json; print(json.load(open('.devcontainer/devcontainer.json'))['name'])" && bash -n .devcontainer/post-create.sh && echo ok`
Expected: `secrets-lab` then `ok`.

- [ ] **Step 4: Commit**

`git add .devcontainer && git commit -m "feat: Codespaces with Docker, kubectl and the lab images ready"`

---

### Task 6: Front page, docs, license

**Files:**
- Create: `README.md`, `testing.md`, `LICENSE`
- Modify: `labs/README.md` (the "Run" section: commands from the repo root, and the Codespaces option)

- [ ] **Step 1: `README.md`** (temporary until the article replaces it)

```markdown
# Secrets lab

Two small experiments about handling secrets, such as API keys and database passwords, in deployments. Each runs in a minute or less and uses no real secrets.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/synacktraa/secrets-lab?quickstart=1) [![labs](https://github.com/synacktraa/secrets-lab/actions/workflows/tests.yml/badge.svg)](https://github.com/synacktraa/secrets-lab/actions/workflows/tests.yml)

| Experiment | The question | Time |
|---|---|---|
| [Leak hunt](labs/1-leak-hunt/) | A fake API key starts in a `.env` file. After the usual steps (git, Docker, Kubernetes), where can someone still read it? | ~1 min |
| [Password rotation](labs/2-rotation/) | What breaks when you change a database password under a running app, and how do you avoid it? | ~30 s |

## Try it

- **In your browser:** click **Open in GitHub Codespaces**. When the editor opens, run these in its terminal:

  ```bash
  bash labs/1-leak-hunt/run.sh
  bash labs/2-rotation/run.sh
  ```

  Codespaces is free within your GitHub account's monthly allowance.
- **Without running anything:** the **labs** badge opens the latest automatic run. Both labs run on every change and every Monday, and the run fails if a result stops matching.
- **On your own computer:** you need Docker. See [labs/README.md](labs/README.md).
```

- [ ] **Step 2: `labs/README.md`, "Run" section**

Replace the "Run" section's first line and command block with:

```markdown
From the repo root, in a codespace or on your own computer:

```bash
bash labs/1-leak-hunt/run.sh
bash labs/2-rotation/run.sh
```
```

- [ ] **Step 3: `testing.md`**

```markdown
# Testing

| What | Command | Needs |
|---|---|---|
| The checker catches broken results | `bash tests/self-test.sh` | bash only; uses the recorded outputs |
| Both labs still show what the article claims | `bash labs/1-leak-hunt/run.sh > leak-hunt.txt`, then `bash labs/2-rotation/run.sh > rotation.txt`, then `bash tests/check-results.sh leak-hunt.txt rotation.txt` | Docker, git, kubectl, Python 3 |

GitHub Actions runs all three on every push to `main`, on pull requests, every Monday and on demand: `.github/workflows/tests.yml`.
```

- [ ] **Step 4: `LICENSE`**: the MIT License text from https://opensource.org/license/mit, with the line `Copyright (c) 2026 synacktraa`.

- [ ] **Step 5: Check the prose**

Run: `python ~/.claude/skills/plain-article-writing/scripts/check.py README.md`
Expected: 0 banned phrases, 0 bold claims, 0 uses of "I".

- [ ] **Step 6: Commit**

`git add -A && git commit -m "docs: front page with Try it links, testing guide, MIT license"`

---

### Task 7: Publish (asks the author first)

- [ ] **Step 1: Ask the author to confirm making the repo public.**
- [ ] **Step 2: Create and push**

Run: `gh repo create synacktraa/secrets-lab --public --source . --push --description "Two small experiments on where secrets leak and how to rotate them without downtime"`
Expected: the repo URL.

- [ ] **Step 3: Wait for the first Actions run**

Run: `gh run watch --repo synacktraa/secrets-lab --exit-status $(gh run list --repo synacktraa/secrets-lab --limit 1 --json databaseId --jq '.[0].databaseId')`
Expected: every step green.

- [ ] **Step 4: The author opens a codespace from the badge and runs both labs.** Expected: both scorecards match `labs/*/output.txt` in pattern.
