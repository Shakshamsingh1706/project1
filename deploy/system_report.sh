#!/usr/bin/env bash
#
# Collect full deployment diagnostic report into deployment_report.txt
# Run from repo root: bash deploy/system_report.sh

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT="$REPO_ROOT/deployment_report.txt"

{
  echo "=============================================="
  echo "DEPLOYMENT DIAGNOSTIC REPORT"
  echo "Generated: $(date -Iseconds 2>/dev/null || date)"
  echo "=============================================="
  echo ""

  echo "--- SYSTEM ---"
  uname -a
  echo ""
  lsb_release -a 2>/dev/null || echo "(lsb_release not available)"
  echo ""
  df -h
  echo ""
  free -h
  echo ""

  echo "--- RUBY ---"
  which ruby
  ruby -v
  which bundle
  bundle -v
  rbenv versions 2>/dev/null || echo "(rbenv not available)"
  echo ""

  echo "--- NODE ---"
  node -v 2>/dev/null || echo "(node not found)"
  yarn -v 2>/dev/null || echo "(yarn not found)"
  echo ""

  echo "--- MYSQL ---"
  systemctl status mysql --no-pager 2>/dev/null || systemctl status mysqld --no-pager 2>/dev/null || echo "(mysql service status not available)"
  echo ""
  mysqladmin -u spree -pspree123 ping 2>/dev/null || echo "(mysqladmin ping failed or not available)"
  echo ""

  echo "--- RAILS ---"
  (cd "$REPO_ROOT/server" && bundle check 2>&1)
  echo ""
  (cd "$REPO_ROOT/server" && RAILS_ENV=production bundle exec rails about 2>&1)
  echo ""

  echo "--- PORTS ---"
  ss -ltnp 2>/dev/null | grep 3000 || echo "(no listener on 3000 or ss failed)"
  echo ""
  ss -ltnp 2>/dev/null | grep puma || echo "(no puma in ss or ss failed)"
  echo ""

  echo "--- SERVICES ---"
  systemctl status spree --no-pager 2>/dev/null || echo "(spree service not found or not available)"
  echo ""
  systemctl status nginx --no-pager 2>/dev/null || echo "(nginx service not found or not available)"
  echo ""

  echo "=============================================="
  echo "END OF REPORT"
  echo "=============================================="
} > "$REPORT" 2>&1

echo "Report saved to deployment_report.txt"
