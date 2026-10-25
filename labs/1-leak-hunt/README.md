# Experiment 1: leak hunt

**Question:** a fake API key starts in a `.env` file. After the usual steps (commit it to git, build a Docker image, write a Kubernetes Secret), where can someone still read it?

```bash
bash run.sh
```

About a minute. Needs Docker (running), git, Python 3 and `kubectl`. See the [lab README](../README.md) for setup and a glossary.

## What the script does

The key is `canary-5f0c2e9a41d7`. It's made up, so any place the script finds it is a copy.

1. **git.** Creates a throwaway repo and commits the `.env` with the key in it. Then it "fixes" the mistake the common way: `git rm --cached .env` (stop tracking the file) plus a `.gitignore` entry. Then it searches the latest commit and the full history.
2. **Docker.** Builds five tiny images, each receiving the key a different way. Then it opens every file in every layer, plus the image's settings, and counts the ones that contain the key:

   | Image | Dockerfile | How the key gets in |
   |---|---|---|
   | `leak-arg` | `dockerfiles/arg.Dockerfile` | as a build argument, used by a `RUN` step |
   | `leak-env` | `dockerfiles/env.Dockerfile` | as a build argument, copied into `ENV` |
   | `leak-copy` | `dockerfiles/copy.Dockerfile` | `COPY . .` copies the whole folder, `.env` included |
   | `leak-copy-ignored` | `dockerfiles/copy.Dockerfile` | the same, but `.env` is listed in `.dockerignore` |
   | `leak-mount` | `dockerfiles/mount.Dockerfile` | a BuildKit secret mount: only one build step can read it |

3. **Kubernetes.** Writes a Secret file with `kubectl create secret ... --dry-run=client` (nothing is sent to a cluster), then decodes its base64.

Everything is created in `work/`, which is wiped at the start of each run, and the five images are deleted at the end.

## Reading the result

The last block is the scorecard. `FOUND` means a readable copy of the key is in that place:

| Row | Result | Why |
|---|---|---|
| git: files in the current commit | not found | the fix removed the file from the latest commit |
| git: history | FOUND | the old commit still has it, and every clone of the repo carries it |
| docker: ARG used in a RUN step | FOUND | `docker history` records the build argument's value |
| docker: ARG promoted to ENV | FOUND | `docker inspect` shows it in the image's settings |
| docker: COPY . . with no .dockerignore | FOUND | the `.env` file sits in a layer at `/app/.env` |
| docker: COPY . . with .env in .dockerignore | not found | Docker skipped the file |
| docker: RUN --mount=type=secret | not found | the key was readable during one step and never saved |
| kubernetes: Secret manifest | FOUND | base64 decodes straight back to the key |

`output.txt` is the run the article quotes. Image IDs and commit hashes change on every run; the `FOUND` / `not found` verdicts shouldn't.

## Files

- `run.sh`: the experiment
- `scan_image.py`: counts the files in a saved image (`docker save`) that contain a string. It stops with a message if a layer is zstd-compressed, which Python's standard library can't read.
- `dockerfiles/`: the four Dockerfiles (`copy.Dockerfile` is built twice)
- `output.txt`: the recorded run
