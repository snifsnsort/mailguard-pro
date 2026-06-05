# MailGuard Pro — Linux Installation Guide

This guide takes you from a fresh Linux server to a running MailGuard Pro in about
15 minutes. No prior knowledge of the system is assumed — just copy each command in
order. Lines starting with `#` are explanations, not commands.

When you finish, MailGuard will be running in your browser at `http://<your-server>:8000`.

---

## What you need before you start

1. **A Linux server** you can SSH into, with `sudo` access. Ubuntu 22.04+ or Debian 12+
   is recommended. 2 CPUs / 4 GB RAM / 20 GB disk is plenty.
2. **Your MailGuard Pro license key** — a long string we provided to you.
3. **A registry access token** — only if we told you the software image is private.
   (If we didn't mention it, skip the login step.)
4. *(Optional)* **Microsoft 365 app credentials** — needed only to scan a tenant. You can
   leave these out now and add them later in the web interface.

---

## Step 1 — Install Docker

Docker is the engine that runs MailGuard. Install it with the official script:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
```

Confirm both Docker and the Compose plugin are present:

```bash
docker --version
docker compose version
```

You should see a version number from each. If `docker compose version` errors, your
Docker is too old — re-run the install script above.

---

## Step 2 — Log in to the software registry *(only if your image is private)*

If we gave you a registry token, run this (paste your token in place of the placeholder):

```bash
echo 'PASTE_YOUR_REGISTRY_TOKEN_HERE' | docker login ghcr.io -u snifsnsort --password-stdin
```

You should see `Login Succeeded`. **If we did not give you a token, skip this step** — the
image is public.

---

## Step 3 — Download the configuration files

```bash
mkdir -p ~/mailguard && cd ~/mailguard
curl -O https://raw.githubusercontent.com/snifsnsort/mailguard-pro/main/docker-compose.yml
curl -O https://raw.githubusercontent.com/snifsnsort/mailguard-pro/main/.env.example
cp .env.example .env
```

Everything from here on happens inside the `~/mailguard` folder.

---

## Step 4 — Generate your secrets

MailGuard needs a few random secret values. Run this and **copy the three lines it prints** —
you'll paste them into your configuration in the next step:

```bash
echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)"
echo "SECRET_KEY=$(openssl rand -hex 32)"
echo "ENCRYPTION_KEY=$(openssl rand -base64 32)"
```

---

## Step 5 — Fill in your configuration

Open the `.env` file in a text editor:

```bash
nano .env
```

Set the values below. **These are required for MailGuard to start:**

| Setting | What to put |
|---|---|
| `MAILGUARD_LICENSE_KEY` | The license key we provided (one line, no quotes, no spaces). |
| `POSTGRES_PASSWORD` | The value from Step 4. **This line is not in the template — add it.** |
| `SECRET_KEY` | The value from Step 4. |
| `ENCRYPTION_KEY` | The value from Step 4. |
| `ADMIN_PASSWORD` | Choose a strong password. **This is how you log in.** |
| `AUTH_MODE` | Leave as `local`. |

Everything else (the `SEED_*` Microsoft 365 fields and the optional API keys) can stay blank
for now — MailGuard will start without them, and you can connect your tenant from the web
interface afterward.

A minimal working `.env` looks like this:

```env
MAILGUARD_LICENSE_KEY=eyJsaWNlbnNlX2lkIjoi...your...key....signature
POSTGRES_PASSWORD=replace-with-step-4-value
SECRET_KEY=replace-with-step-4-value
ENCRYPTION_KEY=replace-with-step-4-value
ADMIN_PASSWORD=ChooseAStrongPassword!
AUTH_MODE=local
```

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X` in nano).

---

## Step 6 — Start MailGuard

```bash
docker compose pull
docker compose up -d
```

The first start downloads the database, applies the database schema, and verifies your
license. Give it 30–60 seconds.

---

## Step 7 — Confirm it's running

Check both containers are up:

```bash
docker compose ps
```

You want the `app` service `running` and `postgres` `healthy`. Then look at the startup log:

```bash
docker compose logs app | tail -n 40
```

The signs of a healthy start are these lines:

```
[license] Valid — tenant=... tier=... expires=...
[license] Revocation check passed
Uvicorn running on http://0.0.0.0:8000
```

Finally, test the health endpoint:

```bash
curl http://localhost:8000/api/health
```

You should get `{"status":"ok","version":"..."}`.

Now open **`http://<your-server-ip>:8000`** in a browser and log in with the password you
set in `ADMIN_PASSWORD`. (If you're testing on the server itself, use `http://localhost:8000`.)

---

## Updating to a new version

When a new version is released you'll see a notice in the app. To update:

```bash
cd ~/mailguard
docker compose pull
docker compose up -d
```

Your data is preserved across updates.

---

## Stopping and removing

```bash
docker compose down        # stop MailGuard, keep your data
docker compose down -v     # stop AND permanently delete the database
```

---

## Troubleshooting

**`POSTGRES_PASSWORD is required` when you run `up`**
You didn't add `POSTGRES_PASSWORD` to `.env`. Re-do Steps 4 and 5.

**The `app` container keeps restarting**
Almost always a license issue. Run:
```bash
docker compose logs app | grep -i license
```
A line like `[startup] LICENSE ERROR: ...` tells you why — usually the key is missing,
expired, or pasted incorrectly. Make sure `MAILGUARD_LICENSE_KEY` is on a single line with
no surrounding quotes or spaces, then `docker compose up -d` again.

**`denied` or `unauthorized` when you run `docker compose pull`**
The image is private — complete Step 2 with the registry token we gave you, then retry.

**Port 8000 is already in use**
Add a line `PORT=8080` (or any free port) to `.env`, run `docker compose up -d` again, and
browse to `:8080` instead.

**You can't reach MailGuard from another computer**
Open the port in the server's firewall, e.g. `sudo ufw allow 8000`, and use the server's IP
address rather than `localhost`.

**The app loads but every action returns a "license has been revoked" message**
Your license was revoked. Contact support to restore access.

---

## Support

[support@mailguard.io](mailto:support@mailguard.io)
