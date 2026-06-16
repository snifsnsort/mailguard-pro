# ============================================================================
#  MailGuard Pro - first-time setup (Windows / PowerShell)
#
#  Generates your security secrets, asks for your license key and an admin
#  password, and writes a ready-to-run .env file.
#
#  Safe to re-run: existing security secrets (database password, encryption key,
#  session key) and any integration keys already in .env are PRESERVED. Re-running
#  never breaks your database or your stored credentials:
#    - Rotating POSTGRES_PASSWORD would fail authentication against the existing
#      PostgreSQL data volume ("password authentication failed for user mailguard").
#    - Rotating ENCRYPTION_KEY would make already-encrypted data (OAuth secret,
#      SAS URL, API keys) impossible to decrypt.
#
#  Run from the MailGuard folder:
#      powershell -ExecutionPolicy Bypass -File .\setup.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

$envPath = Join-Path $PSScriptRoot ".env"

# ── Read a value from the existing .env (empty if the file or key is absent) ─
function Get-EnvValue([string]$key) {
    if (-not (Test-Path $envPath)) { return "" }
    foreach ($line in [System.IO.File]::ReadAllLines($envPath)) {
        if ($line -match ("^" + [regex]::Escape($key) + "=(.*)$")) {
            return $Matches[1]
        }
    }
    return ""
}

$updating = $false
if (Test-Path $envPath) {
    Write-Host ".env already exists."
    Write-Host ""
    Write-Host "Re-running keeps your database password, encryption key, and any integration"
    Write-Host "keys already set, and lets you update your license key and admin password."
    Write-Host "(Press Enter at those prompts to keep the current values.)"
    $ans = Read-Host "Update the existing .env? [y/N]"
    if ($ans -notmatch '^[Yy]$') {
        Write-Host "Keeping existing .env. Nothing changed." -ForegroundColor Yellow
        exit 0
    }
    $updating = $true
}

# ── Guard against a leftover PostgreSQL data volume from a previous install ──
# Postgres only applies POSTGRES_PASSWORD when the volume is first created, so a new
# random password won't match an old volume -> "password authentication failed".
if (-not $updating) {
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerCmd) {
        $vols = ""
        try { $vols = (docker volume ls --format '{{.Name}}' 2>$null) -join "`n" } catch { $vols = "" }
        if ($vols -match '(?m)_postgres_data$') {
            Write-Host ""
            Write-Host "WARNING: a PostgreSQL data volume from a previous install was found." -ForegroundColor Yellow
            Write-Host "A new, randomly generated database password will NOT match that old volume,"
            Write-Host "which causes 'password authentication failed for user `"mailguard`"' at startup."
            Write-Host ""
            Write-Host "  - Fresh reinstall, no data to keep?  Remove the old database first:"
            Write-Host "        docker compose down -v"
            Write-Host "  - Want to keep your existing data?   Restore your previous .env instead"
            Write-Host "        of generating a new one, then skip this script."
            Write-Host ""
            $volAns = Read-Host "Generate a new .env anyway? [y/N]"
            if ($volAns -notmatch '^[Yy]$') {
                Write-Host "Stopped. Reset with 'docker compose down -v' or restore your old .env, then re-run." -ForegroundColor Yellow
                exit 0
            }
        }
    }
}

# ── Secret generators (cryptographically secure) ────────────────────────────
function New-RandomBytes([int]$count) {
    $bytes = New-Object 'System.Byte[]' $count
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return $bytes
}
function New-HexKey([int]$count) {
    ((New-RandomBytes $count) | ForEach-Object { $_.ToString('x2') }) -join ''
}
function New-Base64Key([int]$count) {
    [Convert]::ToBase64String((New-RandomBytes $count))
}

Write-Host ""
Write-Host "Preparing security secrets..." -ForegroundColor Cyan
# Preserve existing secrets; only generate the ones that are missing.
$PostgresPassword = Get-EnvValue "POSTGRES_PASSWORD"; if ([string]::IsNullOrWhiteSpace($PostgresPassword)) { $PostgresPassword = New-HexKey 16 }
$SecretKey        = Get-EnvValue "SECRET_KEY";        if ([string]::IsNullOrWhiteSpace($SecretKey))        { $SecretKey        = New-HexKey 32 }
$EncryptionKey    = Get-EnvValue "ENCRYPTION_KEY";    if ([string]::IsNullOrWhiteSpace($EncryptionKey))    { $EncryptionKey    = New-Base64Key 32 }

# Preserve any integration / tenant values already configured, so a re-run never wipes them.
$SeedTenantName   = Get-EnvValue "SEED_TENANT_NAME"
$SeedTenantDomain = Get-EnvValue "SEED_TENANT_DOMAIN"
$SeedTenantId     = Get-EnvValue "SEED_TENANT_ID"
$SeedClientId     = Get-EnvValue "SEED_CLIENT_ID"
$SeedClientSecret = Get-EnvValue "SEED_CLIENT_SECRET"
$EtApiKey         = Get-EnvValue "ET_API_KEY"
$AnthropicApiKey  = Get-EnvValue "ANTHROPIC_API_KEY"
$AbuseipdbApiKey  = Get-EnvValue "ABUSEIPDB_API_KEY"
$VtApiKey         = Get-EnvValue "VT_API_KEY"
$UrlhausAuthKey   = Get-EnvValue "URLHAUS_AUTH_KEY"
$SpamhausUsername = Get-EnvValue "SPAMHAUS_USERNAME"
$SpamhausKey      = Get-EnvValue "SPAMHAUS_KEY"
$AzureSasUrl      = Get-EnvValue "AZURE_LOOKALIKE_BLOB_SAS_URL"
$AzureConnStr     = Get-EnvValue "AZURE_LOOKALIKE_BLOB_CONNECTION_STRING"

$ExistingLicense  = Get-EnvValue "MAILGUARD_LICENSE_KEY"
$ExistingAdminPw  = Get-EnvValue "ADMIN_PASSWORD"
$ClientId         = Get-EnvValue "MAILGUARD_CLIENT_ID"
$ClientSecret     = Get-EnvValue "MAILGUARD_CLIENT_SECRET"
$RedirectUri      = Get-EnvValue "MAILGUARD_REDIRECT_URI"

# ── License key ─────────────────────────────────────────────────────────────
Write-Host ""
if (-not [string]::IsNullOrWhiteSpace($ExistingLicense)) {
    $License = (Read-Host "MailGuard license key [Enter to keep current]").Trim()
    if ([string]::IsNullOrWhiteSpace($License)) { $License = $ExistingLicense }
} else {
    $License = (Read-Host "Paste your MailGuard license key").Trim()
    while ([string]::IsNullOrWhiteSpace($License)) {
        $License = (Read-Host "License key cannot be empty. Paste it").Trim()
    }
}

# ── Admin password (hidden input) ───────────────────────────────────────────
function Read-Plain([string]$prompt) {
    $sec = Read-Host $prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

Write-Host ""
if (-not [string]::IsNullOrWhiteSpace($ExistingAdminPw)) {
    $AdminPassword = Read-Plain "Admin password [Enter to keep current]"
    if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
        $AdminPassword = $ExistingAdminPw
    } else {
        $AdminPassword2 = Read-Plain "Confirm new admin password"
        while ($AdminPassword -ne $AdminPassword2) {
            Write-Host "Passwords do not match - try again." -ForegroundColor Red
            $AdminPassword  = Read-Plain "Admin password"
            $AdminPassword2 = Read-Plain "Confirm admin password"
        }
    }
} else {
    while ($true) {
        $AdminPassword  = Read-Plain "Choose an admin password (input hidden)"
        $AdminPassword2 = Read-Plain "Confirm admin password"
        if ([string]::IsNullOrWhiteSpace($AdminPassword)) { Write-Host "Password cannot be empty." -ForegroundColor Red; continue }
        if ($AdminPassword -ne $AdminPassword2)           { Write-Host "Passwords do not match - try again." -ForegroundColor Red; continue }
        break
    }
}

# ── Optional: One-Click OAuth (Microsoft 365) ───────────────────────────────
# Only prompt if not already configured. Most people skip this and connect in-app.
if ([string]::IsNullOrWhiteSpace($ClientId)) {
    Write-Host ""
    $enableOauth = Read-Host "Pre-fill Microsoft 365 One-Click OAuth now? Most people skip this (connect in-app later). [y/N]"
    if ($enableOauth -match '^[Yy]$') {
        $ClientId     = (Read-Host "  Azure Application (client) ID").Trim()
        $ClientSecret = Read-Plain "  Client secret (hidden)"
        $RedirectUri  = (Read-Host "  Redirect URI (e.g. https://your-host/api/auth/callback)").Trim()
    }
}

# ── Build .env (string concatenation so special characters are written
#     literally; LF line endings + no BOM so Docker reads values cleanly) ─────
$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$lines = @(
    "# MailGuard Pro environment - generated by setup.ps1 on $stamp"
    "# Re-run setup.ps1 to update the license/admin password - your database password"
    "# and encryption key are preserved automatically. Keep this file private."
    ""
    "# -- License -------------------------------------------------------------"
    "MAILGUARD_LICENSE_KEY=" + $License
    ""
    "# -- Database (required) -------------------------------------------------"
    "# Do NOT change after first start - it must match the PostgreSQL data volume, or"
    "# the app fails with 'password authentication failed for user mailguard'."
    "POSTGRES_PASSWORD=" + $PostgresPassword
    ""
    "# -- Security (auto-generated - do not change or share) ------------------"
    "# Changing ENCRYPTION_KEY makes existing encrypted data (OAuth secret, SAS URL,"
    "# API keys) unreadable. Both keys are preserved automatically on re-run."
    "SECRET_KEY=" + $SecretKey
    "ENCRYPTION_KEY=" + $EncryptionKey
    ""
    "# -- Login ---------------------------------------------------------------"
    "AUTH_MODE=local"
    "ADMIN_PASSWORD=" + $AdminPassword
    ""
    "# -- Network (optional) --------------------------------------------------"
    "# Port MailGuard listens on. Uncomment and change if 8000 is already in use."
    "# PORT=8000"
    ""
    "# -- Microsoft 365 (optional - fill in to auto-register your tenant) -----"
    "SEED_TENANT_NAME=" + $SeedTenantName
    "SEED_TENANT_DOMAIN=" + $SeedTenantDomain
    "SEED_TENANT_ID=" + $SeedTenantId
    "SEED_CLIENT_ID=" + $SeedClientId
    "SEED_CLIENT_SECRET=" + $SeedClientSecret
    ""
    "# One-Click OAuth (optional; you can also set this from the web interface)"
    "MAILGUARD_CLIENT_ID=" + $ClientId
    "MAILGUARD_CLIENT_SECRET=" + $ClientSecret
    "MAILGUARD_REDIRECT_URI=" + $RedirectUri
    ""
    "# -- Optional integrations (add later from the web interface or here) ----"
    "ET_API_KEY=" + $EtApiKey
    "ANTHROPIC_API_KEY=" + $AnthropicApiKey
    "ABUSEIPDB_API_KEY=" + $AbuseipdbApiKey
    "VT_API_KEY=" + $VtApiKey
    "URLHAUS_AUTH_KEY=" + $UrlhausAuthKey
    "SPAMHAUS_USERNAME=" + $SpamhausUsername
    "SPAMHAUS_KEY=" + $SpamhausKey
    ""
    "# -- Lookalike domain monitoring -----------------------------------------"
    "# Read-only Azure Blob SAS URL. Leave blank to use the default shipped with"
    "# MailGuard; override only for a fully isolated environment. Can also be set"
    "# from the web interface."
    "AZURE_LOOKALIKE_BLOB_SAS_URL=" + $AzureSasUrl
    "# First-party only - full account connection string. Leave blank when using SAS."
    "AZURE_LOOKALIKE_BLOB_CONNECTION_STRING=" + $AzureConnStr
)
$content = ($lines -join "`n") + "`n"
[System.IO.File]::WriteAllText($envPath, $content, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "Done. .env written." -ForegroundColor Green
Write-Host ""
Write-Host "Start MailGuard with:" -ForegroundColor Cyan
Write-Host "    docker compose pull"
Write-Host "    docker compose up -d"
Write-Host ""
Write-Host "Then open http://localhost:8000 and log in with the admin password you chose."
