#!/usr/bin/env bash
#
# Install the exact Ruby version required by the Spree server using rbenv and ruby-build.
# Run from repo root: bash deploy/install_ruby.sh
# Non-interactive; uses server/.ruby-version.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUBY_VERSION_FILE="$REPO_ROOT/server/.ruby-version"

if [[ ! -f "$RUBY_VERSION_FILE" ]]; then
  echo "ERROR: server/.ruby-version not found. Cannot determine Ruby version."
  exit 2
fi

RUBY_VERSION="$(cat "$RUBY_VERSION_FILE" | tr -d '\n\r')"
if [[ -z "$RUBY_VERSION" ]]; then
  echo "ERROR: server/.ruby-version is empty."
  exit 2
fi

echo "Installing Ruby $RUBY_VERSION (from server/.ruby-version) via rbenv + ruby-build"

# --- Dependencies (Ubuntu/Debian) ---
export DEBIAN_FRONTEND=noninteractive
if command -v apt-get &>/dev/null; then
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
    pkg-config \
    git \
    curl
fi

# --- rbenv ---
RBENV_ROOT="${RBENV_ROOT:-$HOME/.rbenv}"
RBENV_PLUGINS="$RBENV_ROOT/plugins"

if [[ ! -d "$RBENV_ROOT" ]]; then
  git clone https://github.com/rbenv/rbenv.git "$RBENV_ROOT"
  export PATH="$RBENV_ROOT/bin:$PATH"
  eval "$("$RBENV_ROOT/bin/rbenv" init -)"
else
  export PATH="$RBENV_ROOT/bin:$PATH"
  eval "$("$RBENV_ROOT/bin/rbenv" init -)" 2>/dev/null || true
fi

# --- ruby-build ---
if [[ ! -d "$RBENV_PLUGINS/ruby-build" ]]; then
  git clone https://github.com/rbenv/ruby-build.git "$RBENV_PLUGINS/ruby-build"
fi
export PATH="$RBENV_PLUGINS/ruby-build/bin:$PATH"

# --- Install Ruby ---
if ! rbenv versions --bare 2>/dev/null | grep -qx "$RUBY_VERSION"; then
  rbenv install -s "$RUBY_VERSION"
fi

# --- Set global and local ---
rbenv global "$RUBY_VERSION"
echo "$RUBY_VERSION" > "$RUBY_VERSION_FILE"
echo "Ruby $RUBY_VERSION set as global and written to server/.ruby-version"

# --- Bundler ---
rbenv rehash
gem install bundler
rbenv rehash

echo "Done. Ensure your shell loads rbenv:"
echo "  export PATH=\"\$HOME/.rbenv/bin:\$PATH\""
echo "  eval \"\$(rbenv init -)\""
echo "Then: cd server && bundle install"
