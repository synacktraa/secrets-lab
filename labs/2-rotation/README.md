# Experiment 2: password rotation

**Question:** you change a database password while an app is using it. How many connections fail, and does keeping a second login avoid it?

```bash
bash labs/2-rotation/run.sh
```

About 30 seconds. Needs Docker (running). See the [lab README](../README.md) for setup and a glossary.

## What the script does

It starts a Postgres 17 database in Docker, then runs the same 11-second timeline twice. The timeline is in `scenario.sh`, which runs in a second container next to the database. Two things stay connected the whole time:

- **The app** opens a brand-new connection every 0.1 seconds and logs whether it worked, like a service that keeps scaling or restarting.
- **The pool** is one connection opened at the start and kept open, like a connection pool that never reconnects.

**Run 1, `in-place`: change the password.**

| Time | Step |
|---|---|
| t=3 s | `ALTER ROLE app PASSWORD ...`: the old password stops working |
| t=8 s | the app switches to the new password (the 5-second gap stands in for a redeploy) |

**Run 2, `two-users`: overlap two logins.** "Blue" is the old login and "green" the new one.

| Time | Step |
|---|---|
| t=3 s | create a second login, `app_green`, while `app_blue` still works |
| t=5 s | the app switches to `app_green` |
| t=7 s | `ALTER ROLE app_blue NOLOGIN`: blue can't log in any more |
| t=9 s | `pg_terminate_backend()`: close the connections blue still has open |

## Reading the result

- `result: X of Y new connections failed`: how many of the app's connections were refused.
- `failures from ... successful connections in that window: 0`: every connection during the gap failed, not just some.
- `pool session ... still answering at t=...`: the last time the long-lived connection answered. In `in-place` it keeps answering until the run ends, still logged in with the old password, because Postgres checks the password only when a connection opens. In `two-users`, `NOLOGIN` at t=7 s doesn't stop it either. It ends with `FATAL: terminating connection due to administrator command`, which is `pg_terminate_backend()` at t=9 s.

In the recorded run (`output.txt`), 43 of 95 connections failed in-place and 0 of 95 with two logins. The counts vary by a few between machines; the pattern shouldn't.

## Files

- `run.sh`: starts the database and runs both timelines
- `scenario.sh`: the timeline, the fake app and the pool
- `output.txt`: the recorded run
