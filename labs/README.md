# The labs

Two small experiments that back up the claims in [the article](../README.md). They run in a codespace or on your own machine, use no real secrets, and clean up after themselves.

| # | Experiment | The question it answers | Time |
|---|---|---|---|
| 1 | [Leak hunt](1-leak-hunt/) | A fake API key starts in a `.env` file. After the usual steps (git, Docker, Kubernetes), where can someone still read it? | ~1 min |
| 2 | [Password rotation](2-rotation/) | What breaks when you change a database password under a running app, and how do you avoid it? | ~30 s |

## Before you start

A codespace already has everything below. On your own machine, you need:

- **Docker**, installed and running. Check with `docker info`.
- **Bash**. It's built in on macOS and Linux. On Windows, use Git Bash, which comes with [Git for Windows](https://git-scm.com).
- **For experiment 1 only:** git, Python 3, and `kubectl` (just the command-line tool; you don't need a Kubernetes cluster).

The first run downloads two public images, `python:3.12-slim` and `postgres:17-alpine` (about 420 MB on disk together).

## Run

From the repo root:

```bash
bash labs/1-leak-hunt/run.sh
bash labs/2-rotation/run.sh
```

Each script checks what it needs first and tells you if something is missing. Each folder's README explains what its script does step by step and how to read the output. `output.txt` in each folder is the run the article quotes, recorded on 2026-09-28 on Windows 11 with Docker Engine 29.8.0, git 2.41 and kubectl 1.36.1.

## Words used here

- **Secret**: any value that grants access, such as an API key, a database password or a token.
- **Canary**: a made-up value you plant so you can trace it. It exists nowhere else, so every place you find it is a copy.
- **`.env` file**: a text file of `NAME=value` lines that many apps read at startup.
- **Docker image**: a packaged app. It's built in steps, and the files from each step are saved as a **layer**. Anyone who has the image can open every layer and read its **history** (the commands that built it).
- **Build argument (`ARG`)**: a value passed in while an image is being built.
- **`ENV`**: an environment variable baked into the image. `docker inspect` shows it to anyone who has the image.
- **`.dockerignore`**: a list of files Docker must not copy into an image.
- **BuildKit secret mount**: a way to give a file to one build step without saving it in the image. BuildKit is Docker's build engine and has been the default since Docker Engine 23.
- **Kubernetes Secret**: the object Kubernetes uses to hold secrets. Its values are stored base64-encoded.
- **base64**: a way to write any bytes as plain text. It's an encoding, not encryption: anyone can turn it back with `base64 -d`.
- **Rotation**: replacing a credential with a new one.
- **Role**: Postgres's word for a database user.
- **Connection pool**: a set of database connections an app opens once and keeps reusing.
