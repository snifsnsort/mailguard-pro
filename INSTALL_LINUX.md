# MailGuard Pro — Linux Installation Guide

This guide takes you from a bare Linux server to a running MailGuard Pro. It assumes
no prior experience — follow each step in order and copy each command exactly.

When you finish, MailGuard runs in your browser at `http://YOUR-SERVER:8000`.

---

## Before you start

- A Linux server (Ubuntu 22.04+ or Debian 12+), about 2 CPU / 4 GB RAM / 20 GB disk.
- A way to open a terminal on it (e.g. SSH).
- Your **MailGuard Pro license key** (the long string we provided).
- A **registry token** — only if we told you the software image is private.

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

## Step 5 — Log in to the software registry *(only if your image is private)*

Skip this unless we gave you a token.

```bash
echo 'PASTE_YOUR_TOKEN_HERE' | docker login ghcr.io -u snifsnsort --password-stdin
```

You should see `Login Succeeded`.

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
2. It shows you a setup script. Click **Copy**.
3. Run the script (see *Where to run the script* below) and sign in as a Microsoft 365 **admin**.
4. It prints three values: **Tenant ID**, **Client ID**, **Client Secret**.
5. Paste them into the wizard and click **Save**. From then on, connecting is just signing in.

### Option B — Manual

Same idea: choose **Manual Setup**, run the script, and paste the same three values
(Tenant ID, Client ID, Client Secret) into the three boxes.

### Where to run the script

The script works in **either** of these — pick whichever is easier:

- 🪟 **Windows PowerShell on any PC** — open PowerShell, paste the script, press Enter.
  **Needs no Azure subscription.** A Microsoft sign-in window appears; sign in as an admin.
- ☁️ **Azure Cloud Shell** (`https://shell.azure.com`) — choose *PowerShell* if asked.

> [!IMPORTANT]
> Azure Cloud Shell requires an Azure **subscription**. If your Microsoft 365 tenant
> doesn't have one, Cloud Shell won't open — just run the script in **Windows PowerShell**
> instead. It works exactly the same, and the script installs everything it needs.

> [!TIP]
> **On a remote/headless server**, One-Click signs you in through `http://localhost:8000`.
> From your own computer, open a tunnel first:
> `ssh -L 8000:localhost:8000 your-user@your-server`, then browse `http://localhost:8000`
> locally and click **Connect**. **Manual Setup** has no such requirement — it's often
> simpler on a remote server.

A standalone copy of each script is also included in this folder if you prefer to run it
directly: **`setup-oauth.ps1`** (One-Click) and **`setup-m365.ps1`** (Manual). For example:

```powershell
./setup-oauth.ps1
```

> [!NOTE]
> The scripts only **read** your tenant configuration — they never change mail flow,
> users, or policies. The Exchange role they assign can take up to **30 minutes** to fully
> activate.

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

**`denied` or `unauthorized` when you run `docker compose pull`**
The image is private — complete Step 5 with the token we gave you, then retry.

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
