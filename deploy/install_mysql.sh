#!/usr/bin/env bash
#
# Install MySQL server, create user and database for Spree server.
# User: spree, password: spree123, database: spree_production.
# Run from repo root: bash deploy/install_mysql.sh

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# --- Install MySQL server ---
sudo apt-get update -qq
sudo apt-get install -y -qq mysql-server

# --- Start MySQL (might already be running) ---
sudo systemctl start mysql 2>/dev/null || sudo systemctl start mysqld 2>/dev/null || true
sudo systemctl enable mysql 2>/dev/null || sudo systemctl enable mysqld 2>/dev/null || true

# --- Create user, database, and grant (using root; no password for initial setup on Ubuntu) ---
MYSQL_USER="${MYSQL_USER:-spree}"
MYSQL_PASS="${MYSQL_PASS:-spree123}"
MYSQL_DB="${MYSQL_DB:-spree_production}"

# On Ubuntu 22.04+, root uses auth_socket; we use sudo to run mysql as root
sudo mysql -e "
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASS}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}_cache\`.* TO '${MYSQL_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}_queue\`.* TO '${MYSQL_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}_cable\`.* TO '${MYSQL_USER}'@'localhost';
FLUSH PRIVILEGES;
"

# Create additional databases for solid_cache, solid_queue, solid_cable
for suffix in _cache _queue _cable; do
  sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}${suffix}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true
done
sudo mysql -e "FLUSH PRIVILEGES;"

echo "MySQL is running. Connection: mysql2://${MYSQL_USER}:${MYSQL_PASS}@127.0.0.1/${MYSQL_DB}"
echo "Set in server/.env.production: RAILS_ENV=production, SECRET_KEY_BASE=(run: bundle exec rails secret), DB_ADAPTER=mysql2"
