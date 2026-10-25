# Testing

| What | Command | Needs |
|---|---|---|
| The checker catches broken results | `bash tests/self-test.sh` | bash only; uses the recorded outputs |
| Both labs still show what the article claims | `bash labs/1-leak-hunt/run.sh > leak-hunt.txt`, then `bash labs/2-rotation/run.sh > rotation.txt`, then `bash tests/check-results.sh leak-hunt.txt rotation.txt` | Docker, git, kubectl, Python 3 |

GitHub Actions runs all three on every push to `main`, on pull requests, every Monday and on demand: `.github/workflows/tests.yml`.
