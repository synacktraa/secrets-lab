#!/usr/bin/env bash
# Experiment 1: leak hunt. README.md in this folder explains each step.
#
# Plants one fake API key (the "canary") in a .env file, pushes that file
# through git, five Docker builds and a Kubernetes Secret, then searches each
# result for the key. Runs locally in about a minute and uses no real secrets.
set -uo pipefail

CANARY="canary-5f0c2e9a41d7"   # made up, so any place it turns up is a copy
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/work"              # scratch folder, wiped and recreated on every run
PY="$(command -v python3 || command -v python)"
IMAGES=(leak-arg leak-env leak-copy leak-copy-ignored leak-mount)

need() { command -v "$1" > /dev/null || { echo "missing: $1. $2"; exit 1; }; }
need git "Install Git: https://git-scm.com"
need docker "Install Docker: https://docs.docker.com/get-docker/"
need kubectl "Install kubectl (no cluster needed): https://kubernetes.io/docs/tasks/tools/"
[ -n "$PY" ] || { echo "missing: python3. Install Python 3: https://www.python.org"; exit 1; }
docker info > /dev/null 2>&1 || { echo "Docker is installed but not running. Start it and run this again."; exit 1; }

rm -rf "$WORK" && mkdir -p "$WORK" && cd "$WORK" || exit 1
results=()
record() { results+=("$(printf '%-46s %s' "$1" "$2")"); }
verdict() { if [ "$1" -gt 0 ]; then echo "FOUND"; else echo "not found"; fi; }
label() {
  case "$1" in
    leak-arg)          echo "docker: ARG used in a RUN step" ;;
    leak-env)          echo "docker: ARG promoted to ENV" ;;
    leak-copy)         echo "docker: COPY . . with no .dockerignore" ;;
    leak-copy-ignored) echo "docker: COPY . . with .env in .dockerignore" ;;
    leak-mount)        echo "docker: RUN --mount=type=secret" ;;
  esac
}

# Counts the files in an image (every layer, plus its config) that contain the canary.
scan() {
  docker save "$1" -o "$1.tar" || return 1
  "$PY" "$HERE/scan_image.py" "$1.tar" "$CANARY"
  rm -f "$1.tar"
}

# 1. git: commit the .env by mistake, then "fix" it the usual way.
echo "== 1. git: commit a .env, then 'fix' it with .gitignore"
mkdir repo && cd repo || exit 1
git init -q && git config user.email lab@example.com && git config user.name lab
git config core.autocrlf false
printf 'API_KEY=%s\n' "$CANARY" > .env
echo 'print("hello")' > app.py
git add . && git commit -qm "initial commit"
git rm -q --cached .env && echo ".env" > .gitignore
git add .gitignore && git commit -qm "stop tracking .env"
git log --oneline -S "$CANARY"
record "git: files in the current commit" "$(verdict "$(git grep -l "$CANARY" HEAD -- | wc -l)")"
record "git: history (git log -p)" "$(verdict "$(git log --all -p | grep -c "$CANARY")")"
cd ..

# 2. docker: build five small images, each getting the key a different way.
echo "== 2. docker: five ways to hand a key to a build"
mkdir empty app app-ignored
for d in app app-ignored; do
  printf 'API_KEY=%s\n' "$CANARY" > "$d/.env"
  echo 'print("hello")' > "$d/app.py"
done
echo ".env" > app-ignored/.dockerignore
printf '%s' "$CANARY" > api_key.txt   # outside every build context

docker build -q -f "$HERE/dockerfiles/arg.Dockerfile" --build-arg API_KEY="$CANARY" -t leak-arg empty
docker build -q -f "$HERE/dockerfiles/env.Dockerfile" --build-arg API_KEY="$CANARY" -t leak-env empty
docker build -q -f "$HERE/dockerfiles/copy.Dockerfile" -t leak-copy app
docker build -q -f "$HERE/dockerfiles/copy.Dockerfile" -t leak-copy-ignored app-ignored
docker build -q -f "$HERE/dockerfiles/mount.Dockerfile" --secret id=api_key,src=api_key.txt -t leak-mount empty

for img in "${IMAGES[@]}"; do
  echo "-- $img"
  echo "   docker history --no-trunc: $(docker history --no-trunc "$img" | grep -c "$CANARY") lines"
  echo "   docker inspect (Config.Env): $(docker inspect --format '{{json .Config.Env}}' "$img" | grep -c "$CANARY") lines"
  hits="$(scan "$img")"
  echo "   files containing it (every layer + config): $hits"
  record "$(label "$img")" "$(verdict "$hits")"
done
echo "   docker history of leak-arg, the RUN step:"
docker history --no-trunc --format '{{.CreatedBy}}' leak-arg | grep "$CANARY" | cut -c1-110

# 3. kubernetes: write a Secret manifest (no cluster needed) and decode it.
echo "== 3. kubernetes: a Secret manifest (no cluster needed)"
kubectl create secret generic app-secrets --from-literal=API_KEY="$CANARY" \
  --dry-run=client -o yaml > secret.yaml
grep -A1 '^data:' secret.yaml
encoded="$(awk '/API_KEY:/ {print $2}' secret.yaml)"
decoded="$(printf '%s' "$encoded" | base64 -d)"
echo "   base64 -d -> $decoded"
record "kubernetes: Secret manifest, after base64 -d" "$(verdict "$([ "$decoded" = "$CANARY" ] && echo 1 || echo 0)")"

echo
echo "== where did $CANARY end up?"
printf '%s\n' "${results[@]}"
echo "(FOUND means a readable copy of the key is in that place. README.md explains each row.)"

docker rmi -f "${IMAGES[@]}" > /dev/null
