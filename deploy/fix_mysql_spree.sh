#!/usr/bin/env bash
#
# Fix MySQL for Spree: Barracuda + DYNAMIC row format, recreate DBs, db:prepare, assets.
# Run from repo root: sudo bash deploy/fix_mysql_spree.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$REPO_ROOT/server"

# 1. Edit mysqld.cnf
MYSQLD_CNF="/etc/mysql/mysql.conf.d/mysqld.cnf"
if [[ ! -f "$MYSQLD_CNF" ]]; then
  echo "FAILURE: $MYSQLD_CNF not found"
  exit 1
fi

if ! grep -q "innodb_default_row_format=dynamic" "$MYSQLD_CNF" 2>/dev/null; then
  cat >> "$MYSQLD_CNF" <<'EOF'

# Spree/Barracuda (fix_mysql_spree.sh)
[mysqld]
innodb_file_per_table=1
innodb_file_format=Barracuda
innodb_default_row_format=dynamic
innodb_large_prefix=1
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
EOF
  echo "Appended Barracuda/DYNAMIC settings to $MYSQLD_CNF"
fi

# 2. Restart MySQL
systemctl restart mysql 2>/dev/null || systemctl restart mysqld 2>/dev/null || true
sleep 2

# 3. Recreate databases
mysql -u root <<'SQL'
DROP DATABASE IF EXISTS spree_production;
DROP DATABASE IF EXISTS spree_production_cache;
DROP DATABASE IF EXISTS spree_production_queue;
DROP DATABASE IF EXISTS spree_production_cable;

CREATE DATABASE spree_production CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE spree_production_cache CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE spree_production_queue CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE spree_production_cable CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'spree'@'localhost' IDENTIFIED BY 'spree123';
GRANT ALL PRIVILEGES ON spree_production.* TO 'spree'@'localhost';
GRANT ALL PRIVILEGES ON spree_production_cache.* TO 'spree'@'localhost';
GRANT ALL PRIVILEGES ON spree_production_queue.* TO 'spree'@'localhost';
GRANT ALL PRIVILEGES ON spree_production_cable.* TO 'spree'@'localhost';
FLUSH PRIVILEGES;
SQL

# 4. Clean old Rails state
cd "$SERVER_DIR"
rm -rf tmp/*
rm -f db/schema.rb

# 5. Load environment
if [[ -f "$SERVER_DIR/.env.production" ]]; then
  set -a
  export $(grep -v '^#' "$SERVER_DIR/.env.production" | xargs)
  set +a
fi

# When run as root (sudo), run Rails as the server dir owner so bundle/rbenv are in PATH
run_rails() {
  if [[ "$(id -u)" -eq 0 ]]; then
    local owner
    owner="$(stat -c '%U' "$SERVER_DIR" 2>/dev/null)" || true
    if [[ -n "$owner" ]] && [[ "$owner" != "root" ]]; then
      (cd "$SERVER_DIR" && su - "$owner" -c "cd \"$SERVER_DIR\" && export \$(grep -v '^#' .env.production 2>/dev/null | xargs) && RAILS_ENV=production bundle exec rails $*")
      return
    fi
    for rbenv_home in /home/deploy /home/spree; do
      if [[ -x "$rbenv_home/.rbenv/shims/bundle" ]]; then
        (cd "$SERVER_DIR" && RAILS_ENV=production "$rbenv_home/.rbenv/shims/bundle" exec rails "$@")
        return
      fi
    done
  fi
  (cd "$SERVER_DIR" && RAILS_ENV=production bundle exec rails "$@")
}

# 6. db:prepare
if ! run_rails db:prepare; then
  echo "FAILURE: rails db:prepare failed"
  exit 1
fi

# 7. assets:precompile
if ! run_rails assets:precompile; then
  echo "FAILURE: rails assets:precompile failed"
  exit 1
fi

echo "SUCCESS"
