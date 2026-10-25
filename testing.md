# Testing

| What | Command | Needs |
|---|---|---|
| The checker catches broken results | `bash tests/self-test.sh` | bash only; uses the recorded outputs |
| Both labs still show what the article claims | `bash labs/1-leak-hunt/run.sh > leak-hunt.txt`, then `bash labs/2-rotation/run.sh > rotation.txt`, then `bash tests/check-results.sh leak-hunt.txt rotation.txt` | Docker, git, kubectl, Python 3 |
| The Codespaces setup builds and both labs pass inside it | `npx -y @devcontainers/cli@0.83.3 up --workspace-folder .`, then the lab commands above through `npx -y @devcontainers/cli@0.83.3 exec --workspace-folder . bash -c '...'` | Docker, Node.js |

GitHub Actions runs all of these on every push to `main`, on pull requests, every Monday and on demand: `.github/workflows/tests.yml`. The `labs` job runs the first two; the `codespace` job runs the third.
