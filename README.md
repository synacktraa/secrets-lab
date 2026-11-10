# Where secrets leak on deploy, and how to rotate them

**TL;DR**

- I put a fake API key in a `.env` file, then committed the project to git, built Docker images and wrote a Kubernetes Secret. Five of the eight places I checked had a readable copy of the key.
- Removing the file from git doesn't remove it from the history. If a secret reaches a commit, replace it.
- In Docker, keep `.env` out of the image with `.dockerignore`, and pass build-time secrets with a secret mount instead of a build argument.
- A Kubernetes Secret is base64-encoded, not encrypted.
- Changing a database password in place made 43 of 95 new connections fail. Overlapping two logins made none fail.

A **secret** is a value that grants access, such as an API key, a database password or a token. Many apps read their secrets from a **`.env` file**, a text file of `NAME=value` lines that the app loads when it starts. On your own computer, the file stays where you put it. When you deploy, the usual steps copy files into other places, and the `.env` file can go with them.

This article answers two questions: where does a secret end up when you deploy, and how do you change a secret without breaking the app? I ran an experiment for each, and both are in this repository. You can rerun them in your browser in about a minute, as described in [Try it yourself](#try-it-yourself).

## Where does a secret end up when you deploy?

I created a fake API key, `canary-5f0c2e9a41d7`, and put it in a `.env` file. The value exists nowhere else, so any place it turns up is a copy. Then I committed the project to git, built five Docker images that each received the key in a different way, and wrote a Kubernetes Secret. Finally, I searched every place a copy could be.

![The fake key travels from the .env file to eight places. Readable copy: git history, a build argument used in a RUN step, a build argument copied into ENV, COPY . . with no .dockerignore, and a Kubernetes Secret file. No copy: the latest commit after git rm --cached, COPY . . with .env in .dockerignore, and a secret mount.](docs/diagrams/leak-path.png)

**Git.** I committed the `.env` file, then removed it the way many people do: `git rm --cached .env` and a `.gitignore` entry. The latest commit no longer contained the file, but the commit before it still did. `git rm --cached` only stops git from tracking the file from the next commit on, and everyone who cloned the repository already has the older commit. [GitHub's guide to removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository) says the first step is to revoke or rotate the secret, and that you can't remove the data from other people's clones. So once a secret reaches a commit, treat it as leaked and replace it.

**Docker build arguments.** A Docker **image** is a packaged app, built in steps. The files from each step are saved as a **layer**, and anyone who has the image can read every layer and the commands that built it. A **build argument** (`ARG`) is a value passed in while the image is built. When I passed the key as a build argument and used it in a `RUN` step, `docker history` showed the key. When I copied it into `ENV`, `docker inspect` showed it among the image's settings. [Docker's reference](https://docs.docker.com/reference/dockerfile/#arg) advises against passing secrets as build arguments for this reason.

A **secret mount** (`RUN --mount=type=secret`) kept the key out. It makes a file readable during one build step and doesn't save it in the image. Secret mounts need BuildKit, which has been Docker's default build engine since Docker Engine 23.

**Copying the project folder.** Many Dockerfiles use `COPY . .`, which copies the whole project folder into the image. Without a `.dockerignore` file, that included `.env`, and the key sat in a layer at `/app/.env`. A **`.dockerignore`** file lists files Docker must not copy. With `.env` listed in it, the image had no copy of the key.

**Kubernetes Secrets.** A **Kubernetes Secret** is the object Kubernetes uses to hold a secret value. A Secret file stores each value in **base64**, a way to write any bytes as plain text. Anyone can decode base64, and `base64 -d` turned the value straight back into the key. [Kubernetes' docs](https://kubernetes.io/docs/concepts/configuration/secret/) add that Secrets are stored unencrypted in the cluster's data store by default, and that anyone who can create a Pod in a namespace can read the Secrets in it. Keep Secret files out of git, and limit who can create Pods and read Secrets.

## How do you change a secret without breaking the app?

Replacing a secret with a new one is called **rotation**. You rotate on a schedule, and straight away after a leak like the ones above. While you rotate, the app is still using the old secret, so changing it at the wrong moment breaks the app.

To measure how much, I started a Postgres database and a small app that opens a new connection every 0.1 seconds, like a service that keeps scaling or restarting. The app connects with a **login**, a database user that Postgres calls a role. A second connection stays open for the whole run, as a connection in a connection pool does. Each run lasts 11 seconds, and the app takes 5 seconds to switch to a new password, which stands in for a redeploy.

**Changing the password in place.** At 3 seconds, I changed the login's password with `ALTER ROLE`. Every new connection failed from then until the app switched at 8 seconds: 43 of 95 in total. The open connection kept working until the end of the run, still logged in with the old password. Postgres checked the password when that connection opened and didn't check it again.

The number of failures depends on how long your app takes to pick up the new password. [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotation-strategy.html) calls this the "single user" strategy, and its docs describe a short gap between the password change and the secret update, with "a low risk" of denied calls. In my run, the gap was a 5-second redeploy, and no connection in it succeeded.

**Using two logins.** In the second run, the old and new logins overlapped:

1. At 3 seconds, I created a second login, `app_green`, while the first, `app_blue`, still worked.
2. At 5 seconds, the app switched to `app_green`.
3. At 7 seconds, `ALTER ROLE app_blue NOLOGIN` stopped new logins as `app_blue`.
4. At 9 seconds, `pg_terminate_backend()` closed the connections `app_blue` still had open.

None of the 95 new connections failed, because the app always logged in with a login the database still accepted: it switched to `app_green` at 5 seconds, 2 seconds before `app_blue` stopped working. The open connection showed why the fourth step is needed: `NOLOGIN` didn't end it, and it kept answering as `app_blue` until `pg_terminate_backend()` closed it. AWS Secrets Manager offers a similar "alternating users" strategy and describes it as appropriate for applications that require high availability. Unlike the lab, it keeps both logins valid and alternates which one gets a new password.

![Both runs as timelines from 0 to 11 seconds. Changing the password in place: every new connection fails from 3 to 8 seconds, 43 of 95 in total, while the open connection keeps answering with the old password. Using two logins: app_blue and app_green overlap, no new connection fails, and the open connection as app_blue ends at 9 seconds.](docs/diagrams/rotation.gif)

**Choose two logins** when your app can't afford failed connections during a rotation. **Changing the password in place** is simpler, and it's enough when your app picks up the new password within seconds and retries a failed connection.

## Try it yourself

Both experiments are in [`labs/`](labs/), and each runs in a minute or less. The quickest way to run them is in your browser, with GitHub Codespaces:

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/synacktraa/secrets-lab?quickstart=1)

When the editor opens, run these in its terminal:

```bash
bash labs/1-leak-hunt/run.sh
bash labs/2-rotation/run.sh
```

Codespaces is free within your GitHub account's monthly allowance. To run the labs on your own computer instead, you need Docker; [labs/README.md](labs/README.md) has the details.

You can also see the results without running anything. Both labs [run automatically](https://github.com/synacktraa/secrets-lab/actions/workflows/tests.yml) on every change and every Monday, and the run fails if a result stops matching this article.

## Summary

The usual deploy steps can copy a secret from a `.env` file into places other people can read: git history, a Docker image's history, settings and layers, and Kubernetes Secret files. Keep `.env` out of git with `.gitignore` and out of images with `.dockerignore`, pass build-time secrets with a secret mount, and replace any secret that has reached a commit. To rotate a database password without failed connections, create a second login, switch the app to it, then disable the old login and close its open connections.
