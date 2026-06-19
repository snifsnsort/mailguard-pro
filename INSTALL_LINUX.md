# MailGuard Pro — Linux Installation Guide

This guide takes you from a bare Linux server to a running MailGuard Pro. It assumes
no prior experience — follow each step in order and copy each command exactly.

When you finish, MailGuard runs in your browser at `http://YOUR-SERVER:8000`.

---

## Before you start

- A Linux server (Ubuntu 22.04+ or Debian 12+), about 2 CPU / 4 GB RAM / 20 GB disk.
- A way to open a terminal on it (e.g. SSH).
- Your **MailGuard Pro license key** (the long string we provided).
- A **registry token** — provided with your license; required to download the software.

---

## Step 1 — Open a terminal on the server

If the server is remote, connect from your own computer (use your details):

```bash
ssh your-username@your-server-ip
```

Everything below is typed in this terminal.

## Step 2 — Install the required tools (git + Docker)

Paste this whole block:

```bash
sudo apt update
sudo apt install -y git
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
```

Confirm they installed (each prints a version number):

```bash
git --version
docker --version
docker compose version
```

## Step 3 — Download MailGuard

```bash
git clone https://github.com/snifsnsort/mailguard-pro.git
cd mailguard-pro
```

You are now inside the MailGuard folder. Everything from here happens here.

## Step 4 — Run the setup script

This generates your security secrets and asks for the two things only you know — your
license key and a password for the admin login. It then writes a ready-to-run
configuration file for you.

```bash
bash setup.sh
```

When prompted:
- **Paste your MailGuard license key** (the long string we gave you).
- **Choose an admin password** — this is what you'll log in with. Typing is hidden.

That's the entire configuration — no files to edit by hand.

## Step 5 — Log in to the software registry

The MailGuard image is private, so you must sign in with the registry token we provided
before downloading it.

```bash
echo 'PASTE_YOUR_TOKEN_HERE' | docker login ghcr.io -u snifsnsort --password-stdin
```

You should see `Login Succeeded`. This login is saved, so you only do it once per server
(it's also what lets future `docker compose pull` updates work).

## Step 6 — Start MailGuard

```bash
docker compose pull
docker compose up -d
```

The first start takes 30–60 seconds — it downloads the database and app, sets up the
schema, and verifies your license.

## Step 7 — Confirm it's working

```bash
docker compose ps
docker compose logs app | tail -n 40
```

A healthy start shows these lines in the log:

```
[license] Valid — tenant=... tier=... expires=...
[license] Revocation check passed
Uvicorn running on http://0.0.0.0:8000
```

Test the health endpoint:

```bash
curl http://localhost:8000/api/health
```

You want `{"status":"ok",...}`. Then open **`http://YOUR-SERVER-IP:8000`** in a browser
and log in with the admin password you chose in Step 4.

---

## Connecting Microsoft 365

After you log in, open **Connect → Microsoft 365**. The wizard guides you through
everything. You have two options — both easy:

### Option A — One-Click (recommended)

1. In the wizard, choose **One-Click OAuth**.
2. On Step 1, click **Download .ps1** to save **`MailGuard-OAuth-Setup.ps1`**.
3. Run it as a file (see *Where to run the script* below) and sign in as a Microsoft 365 **admin** with the device code it shows.
4. It prints three values — **Tenant ID**, **Client ID**, **Client Secret** — and saves them to `mailguard-signin-credentials.txt`.
5. Paste them into the wizard and click **Save**, then **Connect** and sign in. MailGuard assigns the Exchange role for you; only if it stays *pending* after ~30 min, run **`MailGuard-OAuth-ExchangeRole.ps1`** from the same folder.

### Option B — Manual

Choose **Manual Setup** and click **Download .ps1** for **`MailGuard-1-Setup.ps1`**. Run it
as a file, then paste the three values (Tenant ID, Client ID, Client Secret) into the boxes.
After the tenant connects, run **`MailGuard-2-ExchangeRole.ps1`** from the same folder to
assign the Exchange role.

### Where to run the script

**Run each script as a file** — don't paste the lines one by one (that breaks the
multi-line commands). Pick whichever machine is easiest; it installs what it needs and
signs you in with a device code (no Azure subscription required):

- 🪟 **Windows** — right-click the file → **Run with PowerShell**.
- 🍎 **Mac** — install PowerShell once (`brew install --cask powershell`), then `pwsh ./MailGuard-OAuth-Setup.ps1`.
- 🐧 **Linux** — install PowerShell 7, then `pwsh ./MailGuard-OAuth-Setup.ps1`.

> [!TIP]
> **On a remote/headless server**, One-Click signs you in through `http://localhost:8000`.
> From your own computer, open a tunnel first:
> `ssh -L 8000:localhost:8000 your-user@your-server`, then browse `http://localhost:8000`
> locally and click **Connect**. **Manual Setup** has no such requirement — it's often
> simpler on a remote server.

Standalone copies of all scripts are included in this folder if you prefer to run them
directly: **`MailGuard-OAuth-Setup.ps1`** (One-Click) and **`MailGuard-1-Setup.ps1`** +
**`MailGuard-2-ExchangeRole.ps1`** (Manual).

> [!NOTE]
> The scripts only **read** your tenant configuration — they never change mail flow,
> users, or policies. The Exchange role can take up to **30 minutes** to fully activate.

### Connecting Google Workspace

Prefer Google Workspace? Open **Connect → Google Workspace** and follow that wizard instead.

---

## Updating to a new version

```bash
cd mailguard-pro
docker compose pull
docker compose up -d
```

Your data is preserved across updates.

## Reinstalling (or moving the folder)

The database lives in a Docker **volume**, not in the project folder — so renaming or
deleting the `mailguard-pro` directory does **not** delete the database, and a fresh
install will reuse the old volume. Because PostgreSQL locks in its password the first
time that volume is created, a brand-new `.env` (with a new `POSTGRES_PASSWORD`) won't
match the old volume, and the app fails with `password authentication failed`.

So when reinstalling, pick one:

- **Keep your data** — copy your previous `.env` into the new folder before starting,
  so `POSTGRES_PASSWORD` still matches the existing volume:
  ```bash
  cp /path/to/old/mailguard-pro/.env ~/mailguard-pro/.env
  docker compose up -d
  ```
- **Start clean** — remove the old database volume, then set up fresh:
  ```bash
  cd ~/mailguard-pro
  docker compose down -v        # deletes the old database volume
  bash setup.sh
  docker compose up -d
  ```

> [!NOTE]
> Re-running `bash setup.sh` in place is safe — it **preserves** your existing database
> password and encryption key (and any integration keys), so it never breaks an
> existing database or your stored credentials.

## Stopping and removing

```bash
docker compose down        # stop, keep your data
docker compose down -v     # stop AND permanently delete the database
```

---

## If something goes wrong

**The `app` container keeps restarting**
Almost always a license problem:
```bash
docker compose logs app | grep -i license
```
A `[startup] LICENSE ERROR: ...` line tells you why — usually the key is missing, expired,
or was pasted incorrectly. Re-run `bash setup.sh` to re-enter it, then `docker compose up -d`.

**`password authentication failed for user "mailguard"` in the logs**
The database is rejecting the app's password. This happens after a **reinstall** or a
changed `POSTGRES_PASSWORD` when an old PostgreSQL data volume is still present: Postgres
keeps the password from when the volume was first created and ignores the new one.
```bash
docker compose logs app | grep -i "authentication failed"
```
- Fresh install with **no data to keep** — reset the database:
  ```bash
  docker compose down -v
  docker compose up -d
  ```
- Need to **keep existing data** — restore the `.env` from your previous install so
  `POSTGRES_PASSWORD` matches the volume, then `docker compose up -d`. Do **not** change
  `POSTGRES_PASSWORD` on an existing database.

**`denied` or `unauthorized` when you run `docker compose pull`**
You're not logged in to the registry — complete Step 5 with the token we gave you, then retry.

**Port 8000 is already in use**
Edit `.env`, uncomment and change `PORT=8080` (or any free port), then `docker compose up -d`
and browse to `:8080`.

**You can't reach MailGuard from another computer**
Open the port in the firewall: `sudo ufw allow 8000`, and use the server's IP address.

**Everything returns a "license has been revoked" message**
Your license was revoked. Contact support to restore access.

---

## Support

[support@mailguard.io](mailto:support@mailguard.io)
