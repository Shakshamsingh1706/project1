#!/usr/bin/env bash
#
# Install PostgreSQL, create user and database for Spree server.
# User: spree, DB: spree_production, password: spree123, local md5 auth.
# Run from repo root: bash deploy/install_postgres.sh

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# --- Install PostgreSQL ---
sudo apt-get update -qq
sudo apt-get install -y -qq postgresql postgresql-contrib

# --- Create user and database ---
PG_USER="${PG_USER:-spree}"
PG_PASS="${PG_PASS:-spree123}"
PG_DB="${PG_DB:-spree_production}"

sudo -u postgres psql -v ON_ERROR_STOP=1 <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$PG_USER') THEN
    CREATE USER $PG_USER WITH PASSWORD '$PG_PASS' CREATEDB;
  ELSE
    ALTER USER $PG_USER WITH PASSWORD '$PG_PASS';
  END IF;
END \$\$;
EOF
if ! sudo -u postgres psql -t -A -c "SELECT 1 FROM pg_database WHERE datname = '$PG_DB'" | grep -q 1; then
  sudo -u postgres createdb -O "$PG_USER" "$PG_DB"
fi
sudo -u postgres psql -d "$PG_DB" -v ON_ERROR_STOP=1 -c "GRANT ALL ON SCHEMA public TO $PG_USER;"

# --- Allow local md5 authentication (TCP to 127.0.0.1) ---
PG_HBA="/etc/postgresql/$(ls /etc/postgresql 2>/dev/null | sort -V | tail -1)/main/pg_hba.conf"
if [[ ! -f "$PG_HBA" ]]; then
  PG_HBA=$(sudo -u postgres psql -t -A -c 'show hba_file' 2>/dev/null | tr -d '\r\n')
fi
if [[ -f "$PG_HBA" ]] && ! sudo grep -q "127.0.0.1/32.*md5" "$PG_HBA" 2>/dev/null; then
  echo "Adding local md5 rule to pg_hba.conf"
  echo "host    all             all             127.0.0.1/32            md5" | sudo tee -a "$PG_HBA" >/dev/null
  echo "host    all             all             ::1/128                 md5" | sudo tee -a "$PG_HBA" >/dev/null
  sudo systemctl reload postgresql 2>/dev/null || true
fi

# --- Enable and start ---
sudo systemctl enable postgresql
sudo systemctl start postgresql

echo "PostgreSQL is running. Connection: postgres://$PG_USER:$PG_PASS@127.0.0.1:5432/$PG_DB"
echo "Set in server/.env.production: DATABASE_URL=postgres://$PG_USER:$PG_PASS@127.0.0.1:5432/$PG_DB"
