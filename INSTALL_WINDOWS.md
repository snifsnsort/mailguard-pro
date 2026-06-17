# 🪟 MailGuard Pro — Windows Installation Guide

This guide takes you from a fresh Windows PC to a running MailGuard, click by click. **No technical experience needed.** Just follow each step in order.

When you finish, MailGuard opens in your web browser at **<http://localhost:8000>**.

---

## ✅ What you need first

- A **Windows 10 or 11** PC (64-bit), with about **4 GB free memory** and **20 GB free disk**.
- Your **MailGuard Pro license key** — the long string we emailed you.
- A **registry token** — provided with your license; required to download the software.
- About **10 minutes**.

> [!TIP]
> Do everything on the same PC you want to run MailGuard on. You don't need a server.

---

## 1️⃣ Install Docker Desktop

Docker is the engine that runs MailGuard. You install it once.

1. Go to 👉 **<https://www.docker.com/products/docker-desktop/>**
2. Click **Download for Windows**, then run the file you downloaded (`Docker Desktop Installer.exe`).
3. Click **OK / Next** through the installer and leave all the boxes at their defaults. If it asks about **WSL 2**, say **yes**.
4. When it finishes, **restart your PC** if it asks you to.
5. Open **Docker Desktop** from your Start Menu. Wait until the little whale icon 🐳 in the bottom-left says **"Engine running"** (green).

> [!IMPORTANT]
> Docker Desktop must be **open and running** every time you use MailGuard. If you reboot, open Docker Desktop again first. You'll know it's ready when the whale icon is green.

---

## 2️⃣ Download MailGuard

The easy way — no extra tools needed:

1. Go to 👉 **<https://github.com/snifsnsort/mailguard-pro>**
2. Click the green **`<> Code`** button, then **Download ZIP**.
3. Find the downloaded `mailguard-pro-main.zip` (usually in your **Downloads** folder).
4. **Right-click it → Extract All… → Extract.** You now have a folder called `mailguard-pro-main`.

> [!NOTE]
> Remember where this folder is. Everything below happens inside it.

---

## 3️⃣ Open PowerShell inside that folder

1. Open the `mailguard-pro-main` folder so you can see `setup.ps1` and `docker-compose.yml` inside it.
2. Click once in the **address bar** at the top of the window (where the folder path is shown).
3. Type **`powershell`** and press **Enter**.

A blue or black text window opens — that's PowerShell, and it's already pointed at the right folder. ✅

---

## 4️⃣ Run the setup

In that PowerShell window, copy-paste this line and press **Enter**:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

It will ask you two things:

- **Paste your MailGuard license key** — right-click in the window to paste, then Enter.
- **Choose an admin password** — this is what you'll log in with. Typing is hidden (you won't see dots — that's normal). You'll type it twice.

When it says **"Done. .env created."** you're configured. There are no files to edit by hand. 🎉

---

## 5️⃣ Sign in to the software registry

The MailGuard image is private, so you must sign in once with the registry token we provided. Paste this — replacing `PASTE_YOUR_TOKEN_HERE` with your token:

```powershell
echo PASTE_YOUR_TOKEN_HERE | docker login ghcr.io -u snifsnsort --password-stdin
```

You should see **`Login Succeeded`**. This login is saved, so you only do it once — it's also what lets future updates (`docker compose pull`) work.

---

## 6️⃣ Start MailGuard

Paste these two lines, pressing **Enter** after each:

```powershell
docker compose pull
docker compose up -d
```

The first start takes **30–60 seconds** — it's downloading the database and app, setting things up, and checking your license.

---

## 7️⃣ Open it 🎉

Open your web browser and go to:

### 👉 **<http://localhost:8000>**

Log in with the **admin password** you chose in Step 4.

> [!TIP]
> Want to confirm it's healthy first? Paste `docker compose ps` in PowerShell — both `app` and `postgres` should say **running**.

---

## 🔗 Connecting Microsoft 365

After you log in, click **Connect → Microsoft 365** and the wizard guides you. You'll have two options — both are easy:

- **One-Click (recommended):** the wizard shows you a setup script. Run it, sign in as a Microsoft 365 admin, and it prints three values (Tenant ID, Client ID, Client Secret). Paste them back in → done. After that, connecting is just signing in.
- **Manual:** same script, you paste the same three values.

**Where do you run the script?** You're on Windows — the easiest place is **right here in PowerShell**, no Azure subscription required:

1. In the wizard, click **Copy** on the setup script.
2. Open a new **PowerShell** window (Start Menu → type *PowerShell* → Enter).
3. **Right-click to paste** the script and press **Enter**.
4. A Microsoft sign-in window pops up — sign in as a Microsoft 365 **admin**.
5. It prints **Tenant ID**, **Client ID**, and **Client Secret**. Copy those into the wizard.

> [!NOTE]
> The wizard also offers **Azure Cloud Shell** as an alternative. That requires an Azure *subscription*. If your tenant doesn't have one, just use Windows PowerShell as above — it works exactly the same.

> [!IMPORTANT]
> The script only **reads** your tenant configuration — it never changes mail flow, users, or policies. One Exchange permission it sets can take up to **30 minutes** to fully activate.

For **Google Workspace**, click **Connect → Google Workspace** and follow that wizard instead.

---

## 🔄 Updating to a new version

Open Docker Desktop, open PowerShell in the MailGuard folder (Steps 3), then:

```powershell
docker compose pull
docker compose up -d
```

Your data is kept across updates. ✅

---

## ⏹️ Stopping it

```powershell
docker compose down        # stop MailGuard, keep all your data
```

> [!CAUTION]
> `docker compose down -v` also **permanently deletes the database** and everything in it. Only use the `-v` version if you truly want to wipe everything.

---

## 🆘 If something goes wrong

> [!WARNING]
> **"running scripts is disabled on this system"** when you run setup
> Use the full command exactly as shown in Step 4 — it starts with `powershell -ExecutionPolicy Bypass -File`. That bypasses the restriction safely for this one script.

**Docker / `docker compose` "not recognized" or "cannot connect"**
Docker Desktop isn't running. Open it from the Start Menu and wait for the whale icon 🐳 to turn green, then try again.

**The `app` container keeps restarting**
Almost always the license key. Run this to see why:
```powershell
docker compose logs app | Select-String -Pattern "license"
```
If the key was mistyped or expired, re-run `powershell -ExecutionPolicy Bypass -File .\setup.ps1` to re-enter it, then `docker compose up -d`.

**`denied` or `unauthorized` when you run `docker compose pull`**
You're not signed in to the registry — do Step 5 with the token we gave you, then retry.

**Port 8000 is already in use**
Open `.env` in Notepad, find the line `# PORT=8000`, remove the `#`, change it to `PORT=8080`, save, then `docker compose up -d` and use **<http://localhost:8080>**.

**"License has been revoked"**
Contact support to restore access.

---

<div align="center">

### Need a hand? We'll walk you through it.

[![Email Support](https://img.shields.io/badge/✉️%20support@mailguard.io-0078D4?style=for-the-badge)](mailto:support@mailguard.io)

</div>
