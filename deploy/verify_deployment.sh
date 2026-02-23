#!/usr/bin/env bash
#
# Spree deployment verification script.
# Targets the Rails app in /server. Run from repo root: bash deploy/verify_deployment.sh
# No interactive input. Prints PASS/FAIL per section and fix commands on failure.

set -uo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="${APP_DIR:-$REPO_ROOT/server}"
PUMA_SOCKET="${PUMA_SOCKET:-/var/www/spree/shared/tmp/sockets/puma.sock}"
SHARED_PATH="${SHARED_PATH:-/var/www/spree/shared}"
RAILS_ENV="${RAILS_ENV:-production}"
export RAILS_ENV

# For Rails we need SECRET_KEY_BASE in production
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -hex 32 2>/dev/null || echo 'dummy_secret_for_verify')}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

section() { echo ""; echo "========== $1 =========="; }
pass()  { echo -e "${GREEN}PASS${NC}: $1"; ((PASSED++)) || true; }
fail()  { echo -e "${RED}FAIL${NC}: $1"; echo -e "${YELLOW}FIX: $2${NC}"; ((FAILED++)) || true; }

# Ensure we're in repo root when resolving paths
cd "$REPO_ROOT"

if [[ ! -d "$APP_DIR" ]]; then
  echo -e "${RED}ERROR: App directory not found: $APP_DIR${NC}"
  echo "FIX: Ensure the repository contains the server app at $APP_DIR (e.g. clone Spree repo and run from repo root)."
  exit 2
fi

echo "Repo root: $REPO_ROOT"
echo "App dir:   $APP_DIR"
echo "Rails env: $RAILS_ENV"
echo ""

# --- RUNTIME ---
section "RUNTIME"

if command -v ruby &>/dev/null; then
  pass "Ruby version: $(ruby -v)"
else
  fail "Ruby not found" "bash deploy/install_ruby.sh  # installs version from server/.ruby-version"
fi

if command -v bundle &>/dev/null; then
  pass "Bundler: $(bundle -v)"
else
  fail "Bundler not found" "gem install bundler"
fi

cd "$APP_DIR"
if bundle install --without development test 2>&1 | tail -5; then
  pass "bundle install"
else
  fail "bundle install failed" "cd $APP_DIR && bundle install --without development test"
fi
cd "$REPO_ROOT"

# --- RAILS BOOT ---
section "RAILS BOOT"

cd "$APP_DIR"
if bundle exec rails about &>/dev/null; then
  pass "rails about"
else
  fail "rails about failed" "cd $APP_DIR && RAILS_ENV=$RAILS_ENV SECRET_KEY_BASE=xxx bundle exec rails about"
fi

if bundle exec rails routes &>/dev/null; then
  pass "rails routes"
else
  fail "rails routes failed" "cd $APP_DIR && bundle exec rails routes"
fi

if bundle exec rails zeitwerk:check &>/dev/null; then
  pass "rails zeitwerk:check"
else
  fail "rails zeitwerk:check failed" "cd $APP_DIR && bundle exec rails zeitwerk:check"
fi
cd "$REPO_ROOT"

# --- DATABASE ---
section "DATABASE"

# Spree server uses MySQL
if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mysqld 2>/dev/null; then
  pass "MySQL service running"
else
  fail "MySQL not running" "bash deploy/install_mysql.sh or sudo systemctl start mysql"
fi
if grep -q "adapter: mysql2" "$APP_DIR/config/database.yml" 2>/dev/null; then
  pass "database.yml uses mysql2"
else
  fail "database.yml not configured for MySQL" "Set adapter: mysql2 in server/config/database.yml"
fi

cd "$APP_DIR"
if bundle exec rails db:prepare &>/dev/null; then
  pass "rails db:prepare"
else
  fail "rails db:prepare failed" "cd $APP_DIR && RAILS_ENV=$RAILS_ENV bundle exec rails db:prepare  # ensure DB_* or DATABASE_URL are set"
fi

if ! bundle exec rails db:migrate:status &>/dev/null; then
  fail "Could not get migration status (DB connection or app boot)" "cd $APP_DIR && bundle exec rails db:migrate:status"
else
  PENDING=$(bundle exec rails db:migrate:status 2>/dev/null | grep -c "down" || true)
  if [[ "${PENDING:-0}" -eq 0 ]]; then
    pass "No pending migrations"
  else
    fail "Pending migrations: $PENDING" "cd $APP_DIR && bundle exec rails db:migrate"
  fi
fi
cd "$REPO_ROOT"

# --- ASSETS ---
section "ASSETS"

cd "$APP_DIR"
if bundle exec rails assets:precompile &>/dev/null; then
  pass "assets:precompile"
else
  fail "assets:precompile failed" "cd $APP_DIR && RAILS_ENV=$RAILS_ENV bundle exec rails assets:precompile"
fi
cd "$REPO_ROOT"

# --- PUMA ---
section "PUMA"

# Use local shared path if we can't write to production path
if ! mkdir -p "$(dirname "$PUMA_SOCKET")" 2>/dev/null; then
  SHARED_PATH="$REPO_ROOT/tmp/verify_shared"
  PUMA_SOCKET="$SHARED_PATH/tmp/sockets/puma.sock"
  mkdir -p "$(dirname "$PUMA_SOCKET")" 2>/dev/null || true
fi
mkdir -p "$(dirname "$PUMA_SOCKET")" "$SHARED_PATH/tmp/pids" 2>/dev/null || true
# Stop any existing puma so we can start daemon
pkill -f "puma.*$APP_DIR" 2>/dev/null || true
sleep 1

cd "$APP_DIR"
# Start Puma in daemon mode; bind to socket for production-like check
if bundle exec puma -d -b "unix://$PUMA_SOCKET" -S "$SHARED_PATH/tmp/pids/puma.state" 2>/dev/null; then
  sleep 2
elif bundle exec puma -d -p 3000 2>/dev/null; then
  sleep 2
fi
cd "$REPO_ROOT"

if [[ -S "$PUMA_SOCKET" ]]; then
  pass "Socket file exists: $PUMA_SOCKET"
elif [[ -f "$PUMA_SOCKET" ]]; then
  fail "Path exists but is not a socket: $PUMA_SOCKET" "rm -f $PUMA_SOCKET && restart Puma with bind unix://$PUMA_SOCKET"
else
  fail "Socket file missing: $PUMA_SOCKET" "Ensure Puma is started with: puma -b unix://$PUMA_SOCKET (and dir exists: mkdir -p $(dirname $PUMA_SOCKET))"
fi

if pgrep -f "puma.*$APP_DIR" &>/dev/null || pgrep -f "puma.*3000" &>/dev/null || lsof "$PUMA_SOCKET" &>/dev/null; then
  pass "Puma process listening"
else
  fail "No Puma process listening" "cd $APP_DIR && bundle exec puma -C config/puma.rb -b unix://$PUMA_SOCKET"
fi

# --- SYSTEMD ---
section "SYSTEMD"

if systemctl is-active --quiet spree 2>/dev/null; then
  pass "systemctl status spree (active)"
elif systemctl status spree &>/dev/null; then
  fail "spree service not active" "sudo systemctl start spree  # and: sudo systemctl enable spree"
else
  fail "spree unit not found" "sudo cp $REPO_ROOT/deploy/spree.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl start spree"
fi

echo ""
echo "--- journalctl -u spree -n 50 ---"
journalctl -u spree -n 50 --no-pager 2>/dev/null || echo "(journalctl not available or no spree unit)"
echo ""

# --- NGINX ---
section "NGINX"

if nginx -t &>/dev/null; then
  pass "nginx -t"
else
  fail "nginx config invalid" "sudo nginx -t  # then fix config and sudo systemctl reload nginx"
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
case "$HTTP_CODE" in
  200) pass "curl localhost -> $HTTP_CODE (OK)" ;;
  302) pass "curl localhost -> $HTTP_CODE (redirect)" ;;
  404) fail "curl localhost -> 404" "Check nginx root and Rails routes; ensure app is mounted at /" ;;
  502) fail "curl localhost -> 502 Bad Gateway" "Puma not running or socket wrong: check nginx upstream and systemctl status spree" ;;
  000) fail "curl localhost failed (connection refused or no route)" "Ensure nginx is running: sudo systemctl start nginx" ;;
  *)   fail "curl localhost -> $HTTP_CODE" "Inspect nginx and Puma logs; check proxy_pass and socket path" ;;
esac

# --- Summary ---
section "SUMMARY"
echo "Passed: $PASSED  Failed: $FAILED"
if [[ $FAILED -gt 0 ]]; then
  echo -e "${RED}Some checks failed. See FIX lines above and deploy/README_DEBUG.md${NC}"
  exit 1
fi
echo -e "${GREEN}All checks passed.${NC}"
exit 0
