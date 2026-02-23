#!/usr/bin/env bash
#
# Provision a fresh Ubuntu 22.04 VM for Spree production.
# Run as root or with sudo. Repo must be cloned or copied to /var/www/spree after.
# Set REPO_URL to clone from (e.g. https://github.com/spree/spree.git).
#
# After: Ensure repo is at /var/www/spree/current (e.g. git clone $REPO_URL /var/www/spree/current)
# then run as deploy: cd /var/www/spree/current/server && bundle install && RAILS_ENV=production bundle exec rails db:prepare && RAILS_ENV=production bundle exec rails assets:precompile
# then: sudo systemctl start spree
# Opening server IP should show Spree homepage.

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/spree/spree.git}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
DEPLOY_HOME="/home/$DEPLOY_USER"
RBENV_ROOT="$DEPLOY_HOME/.rbenv"
DEPLOY_ROOT="/var/www/spree"

export DEBIAN_FRONTEND=noninteractive

# --- Create deploy user ---
if ! id "$DEPLOY_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$DEPLOY_USER"
  echo "$DEPLOY_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart spree, /bin/systemctl start spree, /bin/systemctl stop spree" > /etc/sudoers.d/spree-deploy
  chmod 440 /etc/sudoers.d/spree-deploy
fi

# --- System packages ---
apt-get update -qq
apt-get install -y -qq \
  build-essential libssl-dev libreadline-dev zlib1g-dev libyaml-dev \
  libffi-dev libgdbm-dev libncurses5-dev libxml2-dev libxslt1-dev \
  libcurl4-openssl-dev git curl wget autoconf bison \
  nginx mysql-server default-libmysqlclient-dev \
  nodejs npm

# --- Node 20 + yarn (if node is not 20) ---
NODE_MAJOR=$(node -v 2>/dev/null | sed -n 's/^v\([0-9]*\)\..*/\1/p' || echo "0")
if [[ "${NODE_MAJOR:-0}" -ne 20 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
fi
npm install -g yarn

# --- rbenv + Ruby 3.2.2 as deploy user ---
sudo -u "$DEPLOY_USER" bash -s <<RBENV_SCRIPT
set -e
export HOME=$DEPLOY_HOME
if [[ ! -d $RBENV_ROOT ]]; then
  git clone https://github.com/rbenv/rbenv.git $RBENV_ROOT
  export PATH="\$RBENV_ROOT/bin:\$PATH"
  eval "\$(\$RBENV_ROOT/bin/rbenv init - bash)"
  git clone https://github.com/rbenv/ruby-build.git \$RBENV_ROOT/plugins/ruby-build
fi
export PATH="\$RBENV_ROOT/bin:\$RBENV_ROOT/shims:\$PATH"
eval "\$(\$RBENV_ROOT/bin/rbenv init - bash)"
if ! rbenv versions --bare 2>/dev/null | grep -qx 3.2.2; then
  rbenv install -s 3.2.2
fi
rbenv global 3.2.2
rbenv rehash
gem install bundler
echo 'export PATH="\$HOME/.rbenv/bin:\$HOME/.rbenv/shims:\$PATH"' >> \$HOME/.bashrc
echo 'eval "\$(rbenv init - bash)"' >> \$HOME/.bashrc
RBENV_SCRIPT

# --- Deploy root and shared dirs ---
mkdir -p "$DEPLOY_ROOT"
chown "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_ROOT"
mkdir -p "$DEPLOY_ROOT/shared/tmp/sockets" "$DEPLOY_ROOT/shared/tmp/pids" "$DEPLOY_ROOT/shared/log"
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_ROOT/shared"

# --- Clone repo to current (as deploy) ---
if [[ ! -d "$DEPLOY_ROOT/current/.git" ]]; then
  sudo -u "$DEPLOY_USER" git clone --depth 1 "$REPO_URL" "$DEPLOY_ROOT/current"
else
  (cd "$DEPLOY_ROOT/current" && sudo -u "$DEPLOY_USER" git fetch origin main && git reset --hard origin/main)
fi
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_ROOT/current"

# --- Nginx config ---
cp "$DEPLOY_ROOT/current/deploy/nginx_spree.conf" /etc/nginx/sites-available/spree
ln -sf /etc/nginx/sites-available/spree /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
systemctl enable nginx

# --- Systemd service ---
cp "$DEPLOY_ROOT/current/deploy/spree.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable spree

# --- MySQL: create spree user and DB (idempotent) ---
mysql -e "
CREATE USER IF NOT EXISTS 'spree'@'localhost' IDENTIFIED BY 'spree123';
CREATE DATABASE IF NOT EXISTS spree_production CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS spree_production_cache CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS spree_production_queue CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS spree_production_cable CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL ON spree_production.* TO 'spree'@'localhost';
GRANT ALL ON spree_production_cache.* TO 'spree'@'localhost';
GRANT ALL ON spree_production_queue.* TO 'spree'@'localhost';
GRANT ALL ON spree_production_cable.* TO 'spree'@'localhost';
FLUSH PRIVILEGES;
" 2>/dev/null || true
systemctl start mysql 2>/dev/null || systemctl start mysqld 2>/dev/null || true
systemctl enable mysql 2>/dev/null || systemctl enable mysqld 2>/dev/null || true

# --- Rails: .env.production, bundle, db:prepare, assets (as deploy) ---
SECRET=$(sudo -u "$DEPLOY_USER" bash -c "RBENV_ROOT=$RBENV_ROOT; cd $DEPLOY_ROOT/current/server && \$RBENV_ROOT/shims/bundle exec rails secret 2>/dev/null" || openssl rand -hex 64)
sudo -u "$DEPLOY_USER" bash -c "cat > $DEPLOY_ROOT/current/server/.env.production <<EOF
RAILS_ENV=production
SECRET_KEY_BASE=$SECRET
DB_ADAPTER=mysql2
DB_HOST=127.0.0.1
DB_USER=spree
DB_PASS=spree123
DB_NAME=spree_production
EOF"

sudo -u "$DEPLOY_USER" bash -c "RBENV_ROOT=$RBENV_ROOT; cd $DEPLOY_ROOT/current/server && \$RBENV_ROOT/shims/bundle install --without development test --deployment"
sudo -u "$DEPLOY_USER" bash -c "RBENV_ROOT=$RBENV_ROOT; cd $DEPLOY_ROOT/current/server && RAILS_ENV=production \$RBENV_ROOT/shims/bundle exec rails db:prepare"
sudo -u "$DEPLOY_USER" bash -c "RBENV_ROOT=$RBENV_ROOT; cd $DEPLOY_ROOT/current/server && RAILS_ENV=production \$RBENV_ROOT/shims/bundle exec rails assets:precompile"

# --- Start spree ---
systemctl start spree

echo "Provisioning done. Open http://\$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print \$1}') to see Spree."
