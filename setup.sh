#!/usr/bin/env bash
#
# MailGuard Pro — first-time setup.
#
# Generates the security secrets, collects your license key and a chosen admin
# password, and writes a ready-to-run .env file.
#
# Safe to re-run: existing security secrets (database password, encryption key,
# session key) and any integration keys already in .env are PRESERVED. Re-running
# never breaks your database or your stored credentials:
#   • Rotating POSTGRES_PASSWORD would fail authentication against the existing
#     PostgreSQL data volume ("password authentication failed for user mailguard").
#   • Rotating ENCRYPTION_KEY would make already-encrypted data (OAuth secret,
#     SAS URL, API keys) impossible to decrypt.
# So those values are generated once and kept thereafter.
#
set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE=".env"

command -v openssl >/dev/null 2>&1 || { echo "ERROR: 'openssl' is required but not installed."; exit 1; }

# Read a single value from the existing .env (empty if the file or key is absent).
read_existing() {
  [ -f "$ENV_FILE" ] || return 0
  sed -n "s/^$1=//p" "$ENV_FILE" | head -n1
}

UPDATING="no"
if [ -f "$ENV_FILE" ]; then
  echo ".env already exists."
  echo
  echo "Re-running keeps your database password, encryption key, and any integration"
  echo "keys already set, and lets you update your license key and admin password."
  echo "(Press Enter at those prompts to keep the current values.)"
  read -r -p "Update the existing .env? [y/N] " ans
  case "$ans" in
    y|Y) UPDATING="yes" ;;
    *) echo "Keeping existing .env. Nothing changed."; exit 0 ;;
  esac
fi

# Guard against the most common reinstall failure: a leftover PostgreSQL data volume
# from a previous install. Postgres only applies POSTGRES_PASSWORD when the volume is
# first created, so a freshly generated password won't match an old volume and the app
# fails at startup with: password authentication failed for user "mailguard".
if [ "$UPDATING" = "no" ] && command -v docker >/dev/null 2>&1; then
  if docker volume ls --format '{{.Name}}' 2>/dev/null | grep -Eq '_postgres_data$'; then
    echo
    echo "WARNING: a PostgreSQL data volume from a previous install was found."
    echo "A new, randomly generated database password will NOT match that old volume,"
    echo "which causes 'password authentication failed for user \"mailguard\"' at startup."
    echo
    echo "  - Fresh reinstall, no data to keep?  Remove the old database first:"
    echo "        docker compose down -v"
    echo "  - Want to keep your existing data?   Restore your previous .env instead"
    echo "        of generating a new one, then skip this script."
    echo
    read -r -p "Generate a new .env anyway? [y/N] " vol_ans
    case "$vol_ans" in
      y|Y) : ;;
      *) echo "Stopped. Reset with 'docker compose down -v' or restore your old .env, then re-run."; exit 0 ;;
    esac
  fi
fi

echo "Preparing security secrets..."
# Preserve existing secrets; only generate the ones that are missing.
POSTGRES_PASSWORD="$(read_existing POSTGRES_PASSWORD)"; POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}"
SECRET_KEY="$(read_existing SECRET_KEY)";               SECRET_KEY="${SECRET_KEY:-$(openssl rand -hex 32)}"
ENCRYPTION_KEY="$(read_existing ENCRYPTION_KEY)";       ENCRYPTION_KEY="${ENCRYPTION_KEY:-$(openssl rand -base64 32)}"

# Preserve any integration / tenant values already configured, so a re-run never wipes them.
SEED_TENANT_NAME="$(read_existing SEED_TENANT_NAME)"
SEED_TENANT_DOMAIN="$(read_existing SEED_TENANT_DOMAIN)"
SEED_TENANT_ID="$(read_existing SEED_TENANT_ID)"
SEED_CLIENT_ID="$(read_existing SEED_CLIENT_ID)"
SEED_CLIENT_SECRET="$(read_existing SEED_CLIENT_SECRET)"
ET_API_KEY="$(read_existing ET_API_KEY)"
ANTHROPIC_API_KEY="$(read_existing ANTHROPIC_API_KEY)"
ABUSEIPDB_API_KEY="$(read_existing ABUSEIPDB_API_KEY)"
VT_API_KEY="$(read_existing VT_API_KEY)"
URLHAUS_AUTH_KEY="$(read_existing URLHAUS_AUTH_KEY)"
SPAMHAUS_USERNAME="$(read_existing SPAMHAUS_USERNAME)"
SPAMHAUS_KEY="$(read_existing SPAMHAUS_KEY)"
AZURE_LOOKALIKE_BLOB_SAS_URL="$(read_existing AZURE_LOOKALIKE_BLOB_SAS_URL)"
AZURE_LOOKALIKE_BLOB_CONNECTION_STRING="$(read_existing AZURE_LOOKALIKE_BLOB_CONNECTION_STRING)"

EXISTING_LICENSE="$(read_existing MAILGUARD_LICENSE_KEY)"
EXISTING_ADMIN_PASSWORD="$(read_existing ADMIN_PASSWORD)"
MAILGUARD_CLIENT_ID="$(read_existing MAILGUARD_CLIENT_ID)"
MAILGUARD_CLIENT_SECRET="$(read_existing MAILGUARD_CLIENT_SECRET)"
MAILGUARD_REDIRECT_URI="$(read_existing MAILGUARD_REDIRECT_URI)"

echo
if [ -n "$EXISTING_LICENSE" ]; then
  read -r -p "MailGuard license key [Enter to keep current]: " LICENSE_KEY
  LICENSE_KEY="${LICENSE_KEY:-$EXISTING_LICENSE}"
else
  read -r -p "Paste your MailGuard license key: " LICENSE_KEY
  while [ -z "$LICENSE_KEY" ]; do
    read -r -p "License key cannot be empty. Paste it: " LICENSE_KEY
  done
fi

echo
if [ -n "$EXISTING_ADMIN_PASSWORD" ]; then
  read -r -s -p "Admin password [Enter to keep current]: " ADMIN_PASSWORD; echo
  if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD="$EXISTING_ADMIN_PASSWORD"
  else
    read -r -s -p "Confirm new admin password: " ADMIN_PASSWORD2; echo
    while [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD2" ]; do
      echo "Passwords do not match - try again."
      read -r -s -p "Admin password: " ADMIN_PASSWORD; echo
      read -r -s -p "Confirm admin password: " ADMIN_PASSWORD2; echo
    done
  fi
else
  while true; do
    read -r -s -p "Choose an admin password (input hidden): " ADMIN_PASSWORD; echo
    read -r -s -p "Confirm admin password: " ADMIN_PASSWORD2; echo
    if [ -z "$ADMIN_PASSWORD" ]; then echo "Password cannot be empty."; continue; fi
    if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD2" ]; then echo "Passwords do not match - try again."; continue; fi
    break
  done
fi

# Optional: One-Click OAuth (Microsoft 365). Only prompt if not already configured.
# Requires the customer's own Azure app AND the instance served over HTTPS.
if [ -z "$MAILGUARD_CLIENT_ID" ]; then
  echo
  read -r -p "Pre-fill Microsoft 365 One-Click OAuth now? Most people skip this (connect in-app later). [y/N] " enable_oauth
  case "$enable_oauth" in
    y|Y)
      read -r -p "  Azure Application (client) ID: " MAILGUARD_CLIENT_ID
      read -r -s -p "  Client secret (hidden): " MAILGUARD_CLIENT_SECRET; echo
      read -r -p "  Redirect URI (https://your-host/api/auth/callback): " MAILGUARD_REDIRECT_URI
      ;;
  esac
fi

# Write a clean, complete .env. Values are already expanded into shell variables,
# so special characters in passwords/keys/SAS tokens are written literally and safely.
cat > "$ENV_FILE" <<EOF
# MailGuard Pro environment — generated by setup.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Re-run ./setup.sh to update the license/admin password — your database password
# and encryption key are preserved automatically. Keep this file private.

# ── License ───────────────────────────────────────────────────────────────────
MAILGUARD_LICENSE_KEY=${LICENSE_KEY}

# ── Database (required) ───────────────────────────────────────────────────────
# Do NOT change after first start — it must match the PostgreSQL data volume, or
# the app fails with 'password authentication failed for user "mailguard"'.
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# ── Security (auto-generated — do not change or share) ────────────────────────
# Changing ENCRYPTION_KEY makes existing encrypted data (OAuth secret, SAS URL,
# API keys) unreadable. Both keys are preserved automatically on re-run.
SECRET_KEY=${SECRET_KEY}
ENCRYPTION_KEY=${ENCRYPTION_KEY}

# ── Login ─────────────────────────────────────────────────────────────────────
AUTH_MODE=local
ADMIN_PASSWORD=${ADMIN_PASSWORD}

# ── Network (optional) ────────────────────────────────────────────────────────
# Port MailGuard listens on. Uncomment and change if 8000 is already in use.
# PORT=8000

# ── Microsoft 365 (optional — fill in to auto-register your tenant) ───────────
SEED_TENANT_NAME=${SEED_TENANT_NAME}
SEED_TENANT_DOMAIN=${SEED_TENANT_DOMAIN}
SEED_TENANT_ID=${SEED_TENANT_ID}
SEED_CLIENT_ID=${SEED_CLIENT_ID}
SEED_CLIENT_SECRET=${SEED_CLIENT_SECRET}

# One-Click OAuth (optional; needs your own Azure app + HTTPS)
MAILGUARD_CLIENT_ID=${MAILGUARD_CLIENT_ID}
MAILGUARD_CLIENT_SECRET=${MAILGUARD_CLIENT_SECRET}
MAILGUARD_REDIRECT_URI=${MAILGUARD_REDIRECT_URI}

# ── Optional integrations (add later from the web interface or here) ──────────
ET_API_KEY=${ET_API_KEY}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
ABUSEIPDB_API_KEY=${ABUSEIPDB_API_KEY}
VT_API_KEY=${VT_API_KEY}
URLHAUS_AUTH_KEY=${URLHAUS_AUTH_KEY}
SPAMHAUS_USERNAME=${SPAMHAUS_USERNAME}
SPAMHAUS_KEY=${SPAMHAUS_KEY}

# ── Lookalike domain monitoring ───────────────────────────────────────────────
# Read-only Azure Blob SAS URL provided with your license. Until set, the Domain
# Exposure page shows "not provisioned" (you can also paste it in the web interface
# under Settings -> Security Integrations / the Domain Exposure page).
AZURE_LOOKALIKE_BLOB_SAS_URL=${AZURE_LOOKALIKE_BLOB_SAS_URL}
# First-party only — full account connection string. Leave blank when using the SAS URL.
AZURE_LOOKALIKE_BLOB_CONNECTION_STRING=${AZURE_LOOKALIKE_BLOB_CONNECTION_STRING}
EOF

chmod 600 "$ENV_FILE"

echo
echo "Done. .env written and locked down (chmod 600)."
echo
echo "Start MailGuard with:"
echo "    docker compose pull"
echo "    docker compose up -d"
echo
echo "To connect a Microsoft 365 or Google Workspace tenant later, either fill the"
echo "SEED_ lines in .env, or add the tenant from the web interface after logging in."
