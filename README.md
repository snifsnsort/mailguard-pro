# MailGuard Pro

Email Attack Path Intelligence for Microsoft 365 and Google Workspace.

## Requirements

- Docker Desktop (Windows / Mac) or Docker Engine (Linux)
- A MailGuard Pro license key
- Microsoft 365 or Google Workspace tenant credentials

## Install in 3 steps

**1. Download the compose file**

```bash
curl -O https://raw.githubusercontent.com/snifsnsort/mailguard-pro/main/docker-compose.yml
curl -O https://raw.githubusercontent.com/snifsnsort/mailguard-pro/main/.env.example
```

**2. Configure your environment**

```bash
cp .env.example .env
# Open .env in your editor and fill in your credentials
```

**3. Start MailGuard**

```bash
docker compose up -d
```

Open [http://localhost:8000](http://localhost:8000) in your browser.

## Updating

When a new version is available you will see a notification inside the app. To update:

```bash
docker compose pull
docker compose up -d
```

## MSP / Multi-tenant mode

Set `MULTI_TENANT_MODE=true` and `AUTH_MODE=idp` in your `.env`. Each client authenticates with their own Microsoft or Google account and sees only their data.

## Support

[support@mailguard.io](mailto:support@mailguard.io)
