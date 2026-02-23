#!/usr/bin/env bash
#
# First boot: bundle install, db:prepare, assets:precompile, then start Puma in foreground.
# Run from repo root: bash deploy/first_boot.sh
# Loads server/.env.production if present.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$REPO_ROOT/server"
ENV_FILE="$SERVER_DIR/.env.production"

if [[ ! -d "$SERVER_DIR" ]]; then
  echo "ERROR: server directory not found: $SERVER_DIR"
  exit 2
fi

# Load .env.production into environment
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
  echo "Loaded $ENV_FILE"
fi

# Replace placeholder SECRET_KEY_BASE so Rails can boot
if [[ "${SECRET_KEY_BASE:-}" == "generate" ]] || [[ -z "${SECRET_KEY_BASE:-}" ]]; then
  export SECRET_KEY_BASE=$(cd "$SERVER_DIR" && bundle exec rails secret 2>/dev/null || openssl rand -hex 64)
  echo "Generated SECRET_KEY_BASE for this run. For production, set it in server/.env.production"
fi

cd "$SERVER_DIR"
bundle install
bundle exec rails db:prepare
bundle exec rails assets:precompile

# Use shared path so Puma creates the socket Nginx expects (/var/www/spree/shared when deployed)
SHARED="${SPREE_SHARED_PATH:-$REPO_ROOT/../shared}"
mkdir -p "$SHARED/tmp/sockets" "$SHARED/tmp/pids"
export SPREE_SHARED_PATH="$SHARED"
echo "Puma socket: $SHARED/tmp/sockets/puma.sock"

echo "Starting Puma in foreground (Ctrl+C to stop)..."
exec bundle exec puma -C config/puma.rb
