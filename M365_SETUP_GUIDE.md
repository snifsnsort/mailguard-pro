# Connecting Microsoft 365 to MailGuard

This is a one-time, ~10-minute setup done by a **Microsoft 365 Global Administrator**.
It registers a **read-only** app so MailGuard can assess your email security posture.
Nothing is changed in your tenant beyond granting read access.

There are two ways to connect, both read-only. **One-Click (recommended)** lets your
admins connect just by signing in; **Manual** connects with three pasted values. Either
way you run small PowerShell scripts — download them from inside MailGuard (the **Connect
Microsoft 365** screen has a **Download .ps1** button on each step), or use the copies
provided with your install.

---

## Before you start: PowerShell

The scripts use PowerShell 7 modules and work the same on every platform.

| OS | What to do |
|----|------------|
| **Windows** | Nothing to install. Use the built-in PowerShell. |
| **Mac** | Install PowerShell once: `brew install --cask powershell` |
| **Linux** | Install PowerShell 7 for your distro |

Always **run the scripts as files** — do not copy and paste the lines one by one
(pasting breaks multi-line commands).

- **Windows:** right-click the file → **Run with PowerShell**
- **Mac / Linux:** `pwsh ./MailGuard-1-Setup.ps1`

You'll be asked to sign in using a **device code**: a short code and a URL appear in the
window; open the URL in a browser, enter the code, and sign in as a Global Administrator.

---

## One-Click (recommended)

One-Click lets your admins connect by signing in — no connection string to copy.

1. On the **Connect Microsoft 365** screen, choose **One-Click OAuth** and download
   **`MailGuard-OAuth-Setup.ps1`** from Step 1.
2. Run it (device-code sign-in as a Global Administrator). It registers the sign-in app,
   creates a secret, and prints/saves your **Tenant ID**, **Client ID**, and **Client
   Secret** to `mailguard-signin-credentials.txt`.
3. Paste those three values into the wizard and **Save**, then click **Connect** and sign
   in. MailGuard provisions the read-only permissions and assigns the Exchange role for you.
4. **Only if Exchange stays "pending"** after ~30 minutes, run
   **`MailGuard-OAuth-ExchangeRole.ps1`** from the same folder to assign the **View-Only
   Organization Management** role to the sign-in app manually.

> The **Client Secret is shown only once.** It's saved to `mailguard-signin-credentials.txt`
> — **delete that file** once MailGuard shows the tenant connected.

---

## Manual setup

The Manual path registers a separate read-only app (`MailGuard Scanner`) and connects with
three pasted values. It uses two scripts.

## Step 1 — Register the app (`MailGuard-1-Setup.ps1`)

Run `MailGuard-1-Setup.ps1`. It will:

1. Install the required PowerShell modules (first run only).
2. Sign you in to Microsoft 365 (device code).
3. Register the read-only app, grant admin consent, and create a client secret.
4. Print your **Tenant ID**, **Client ID**, and **Client Secret**, and save them to
   `mailguard-credentials.txt` in the same folder.

Then, in MailGuard's **Connect Microsoft 365** screen, paste those three values and
connect. The tenant should show as connected.

> The **Client Secret is shown only once.** It's saved to `mailguard-credentials.txt`
> so you don't lose it. **Delete that file** once MailGuard shows the tenant connected.

## Step 2 — Assign the Exchange role (`MailGuard-2-ExchangeRole.ps1`)

After MailGuard shows the tenant connected, run `MailGuard-2-ExchangeRole.ps1` **from the
same folder** (so it can read `mailguard-credentials.txt`; otherwise it will prompt you).
It signs you in to Exchange Online (device code) and grants the read-only
**View-Only Organization Management** role, then prints a single **SUCCESS** or **ERROR**.

Exchange permissions can take up to ~30 minutes to propagate. Once they do, MailGuard's
mail-flow and transport-rule checks activate automatically.

---

## Troubleshooting

**"Could not install module" / "currently in use" warning**
Close all other PowerShell windows, open a fresh one, and run the script again.

**Sign-in window shows a code instead of a browser popup**
That's expected — it's device-code sign-in. Open the URL shown, enter the code, sign in.

**Step 2 says the module isn't found**
Run Step 1 first (it installs the module), then run Step 2.

**Exchange still shows "pending" after Step 2 succeeded**
Give it up to 30 minutes to propagate. If it never activates, re-run Step 2 and confirm
it prints SUCCESS.

**`ERROR` mentions the role couldn't be assigned**
Make sure you signed in as a Global Administrator. The role can't be granted from the
Azure portal UI — Step 2 is the supported way to assign it.
