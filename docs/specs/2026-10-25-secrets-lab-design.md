# Secrets lab: design

Approved 2026-10-25.

## Goal

A public repo, `synacktraa/secrets-lab`, that holds an article about handling secrets plus the two experiments behind it. A reader can try the experiments in a browser with no local setup, or see a real run without running anything.

## Decisions

- **The front page is the article.** `README.md` will be the article. Until it's written, `README.md` is a short intro with the "Try it" links.
- **The experiments live in `labs/`.** They move over unchanged from the earlier private copy; only the paths in the docs change.
- **No hosting-platform setup.** The post is for the author's own blog, so nothing in the repo ties it to one platform.
- **Private material stays private.** Earlier article drafts and the fact-check sheet aren't part of this repo.

## Layout

```
secrets-lab/
├── README.md                      the article (for now: intro + "Try it")
├── labs/
│   ├── README.md                  setup and glossary
│   ├── 1-leak-hunt/               run.sh, scan_image.py, dockerfiles/, README.md, output.txt
│   └── 2-rotation/                run.sh, scenario.sh, README.md, output.txt
├── tests/
│   ├── check-results.sh           compares a lab run with the article's claims
│   └── self-test.sh               proves the checker passes on good runs and fails on broken ones
├── .devcontainer/                 GitHub Codespaces setup
├── .github/workflows/tests.yml    runs the self-test and both labs
├── testing.md                     how to run every check
├── LICENSE                        MIT
└── docs/specs, docs/plans
```

## Three ways to try it

1. **Codespaces.** An "Open in GitHub Codespaces" badge opens the repo in a browser editor. The dev container is `mcr.microsoft.com/devcontainers/python:3.12`, plus the `docker-in-docker:4` and `kubectl-helm-minikube:1` features (kubectl only). A post-create script waits for Docker, then pulls `python:3.12-slim` and `postgres:17-alpine`, so the first run doesn't wait on downloads. Usage comes from the reader's own GitHub allowance.
2. **A real run, without running anything.** GitHub Actions runs everything on pushes to `main`, on pull requests, every Monday at 06:00 UTC and on demand. The weekly run catches an image update that breaks a lab. A status badge links to the runs, and the outputs are kept as a downloadable artifact.
3. **Locally.** `bash labs/1-leak-hunt/run.sh` and `bash labs/2-rotation/run.sh`, with Docker installed.

## What "the results match the article" means

`tests/check-results.sh LEAK_OUTPUT ROTATION_OUTPUT` fails, naming each claim that broke, unless all of these hold:

| Lab | Claim |
|---|---|
| Leak hunt | The 8-line scorecard matches exactly: FOUND for git history, ARG, ENV, `COPY . .` without `.dockerignore`, and the Kubernetes Secret; not found for the current commit, `.dockerignore`, and the secret mount |
| Rotation, in-place | Some new connections failed |
| Rotation, in-place | No new connection succeeded during the gap |
| Rotation, in-place | The long-lived connection still answered at t ≥ 10 s, long after the password changed at t = 3 s |
| Rotation, two-users | No new connection failed |
| Rotation, two-users | The long-lived connection still answered after `NOLOGIN` at t = 7 s |
| Rotation, two-users | The long-lived connection was ended by `pg_terminate_backend()` |

Exact connection counts aren't checked, because they vary by a few between machines.

## Testing

- `tests/self-test.sh` runs the checker against the recorded outputs (it must pass) and against copies with one claim broken (each must fail). It needs only bash, so it runs first in CI.
- Both labs run locally from the new paths, and the checker passes on the fresh output.
- The first GitHub Actions run passes.
- The author opens one codespace from the badge and runs both labs once.

## Out of scope

Killercoda scenarios, a one-click deploy template, prebuilt codespaces, and the article text itself.
