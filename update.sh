#!/usr/bin/env bash
# MailGuard self-hosted update helper.
#
# Pulls the latest images, restarts the stack, and reclaims disk from the old
# image layers that every `docker compose pull` leaves behind. This is what
# fills a small VM disk over time and can crash Postgres ("No space left on
# device"). Run this instead of the manual pull/up commands.
#
# SAFETY: this NEVER removes volumes. Your database lives in the `postgres_data`
# volume and is left completely untouched. Do not add `--volumes` to any prune.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Pulling latest images..."
docker compose pull

echo "==> Restarting stack..."
docker compose up -d

echo "==> Reclaiming disk from unused images + build cache (volumes untouched)..."
docker image prune -f
docker builder prune -f >/dev/null 2>&1 || true

echo
echo "==> Disk usage:"
df -h /
echo
docker system df

echo
echo "==> Done."
echo "    If '/' is still above ~80% used, run a deeper (still volume-safe) clean:"
echo "        docker image prune -a -f"
