#!/usr/bin/env bash
#
# Non-interactive, idempotent runtime setup for Spree server.
# Run from repo root: bash deploy/bootstrap_runtime.sh
# Then: exec $SHELL  (to reload env), then bash deploy/first_app_boot.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUBY_VERSION_FILE="$REPO_ROOT/server/.ruby-version"

export DEBIAN_FRONTEND=noninteractive

# --- System dependencies ---
echo "[bootstrap] Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
  build-essential \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev \
  libyaml-dev \
  libffi-dev \
  libgdbm-dev \
  libncurses5-dev \
  libxml2-dev \
  libxslt1-dev \
  libpq-dev \
  libsqlite3-dev \
  libcurl4-openssl-dev \
  git \
  curl \
  wget \
  autoconf \
  bison \
  nodejs \
  npm \
  default-libmysqlclient-dev

# --- rbenv ---
RBENV_ROOT="${RBENV_ROOT:-$HOME/.rbenv}"
if [[ ! -d "$RBENV_ROOT" ]]; then
  echo "[bootstrap] Installing rbenv to $RBENV_ROOT"
  git clone https://github.com/rbenv/rbenv.git "$RBENV_ROOT"
else
  echo "[bootstrap] rbenv already present at $RBENV_ROOT"
fi

export PATH="$RBENV_ROOT/bin:$PATH"
eval "$("$RBENV_ROOT/bin/rbenv" init - bash 2>/dev/null)" || true

# --- ruby-build ---
if [[ ! -d "$RBENV_ROOT/plugins/ruby-build" ]]; then
  echo "[bootstrap] Installing ruby-build plugin"
  git clone https://github.com/rbenv/ruby-build.git "$RBENV_ROOT/plugins/ruby-build"
else
  echo "[bootstrap] ruby-build already present"
fi
export PATH="$RBENV_ROOT/plugins/ruby-build/bin:$PATH"

# --- Add rbenv to ~/.bashrc if not already ---
RBENV_BLOCK='export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"'
if ! grep -q 'rbenv init' ~/.bashrc 2>/dev/null; then
  echo "" >> ~/.bashrc
  echo "# rbenv (added by deploy/bootstrap_runtime.sh)" >> ~/.bashrc
  echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
  echo 'eval "$(rbenv init - bash)"' >> ~/.bashrc
  echo "[bootstrap] Added rbenv to ~/.bashrc"
fi
# Make rbenv and shims available in this script (no reliance on .bashrc)
export PATH="$RBENV_ROOT/bin:$RBENV_ROOT/shims:$PATH"
eval "$("$RBENV_ROOT/bin/rbenv" init - bash)" 2>/dev/null || true

# --- Ruby install ---
if [[ ! -f "$RUBY_VERSION_FILE" ]]; then
  echo "ERROR: server/.ruby-version not found at $RUBY_VERSION_FILE"
  exit 2
fi
RUBY_VERSION="$(cat "$RUBY_VERSION_FILE" | tr -d '\n\r')"
if [[ -z "$RUBY_VERSION" ]]; then
  echo "ERROR: server/.ruby-version is empty"
  exit 2
fi

if ! rbenv versions --bare 2>/dev/null | grep -qx "$RUBY_VERSION"; then
  echo "[bootstrap] Installing Ruby $RUBY_VERSION"
  rbenv install -s "$RUBY_VERSION"
else
  echo "[bootstrap] Ruby $RUBY_VERSION already installed"
fi

rbenv global "$RUBY_VERSION"
rbenv rehash
if ! gem list bundler -i &>/dev/null; then
  gem install bundler
  rbenv rehash
fi

echo "[bootstrap] Ruby: $(ruby -v)"
echo "[bootstrap] Bundler: $(bundle -v)"

# --- Node 20 LTS ---
if ! command -v node &>/dev/null; then
  NODE_MAJOR=0
else
  NODE_MAJOR=$(node -v 2>/dev/null | sed -n 's/^v\([0-9]*\)\..*/\1/p' || echo "0")
fi
if [[ "${NODE_MAJOR:-0}" -ne 20 ]]; then
  echo "[bootstrap] Installing Node 20 LTS (NodeSource)"
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y -qq nodejs
else
  echo "[bootstrap] Node 20 already present: $(node -v)"
fi

if ! command -v yarn &>/dev/null; then
  echo "[bootstrap] Installing yarn globally"
  sudo npm install -g yarn
else
  echo "[bootstrap] yarn already present"
fi

echo "[bootstrap] Node: $(node -v)"
echo "[bootstrap] Yarn: $(yarn -v)"

# --- Post-install: bundle install in server ---
echo "[bootstrap] Running bundle install in server..."
cd "$REPO_ROOT/server"
if ! bundle install; then
  echo "ERROR: bundle install failed in server/"
  exit 1
fi
echo "[bootstrap] Done. Run: exec \$SHELL  then  bash deploy/first_app_boot.sh"
