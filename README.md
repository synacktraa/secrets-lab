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
