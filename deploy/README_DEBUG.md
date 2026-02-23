# Spree Deployment Debug Guide

This document explains each failure reported by `deploy/verify_deployment.sh`, whether it is **DevOps** (environment, services, paths) or **Application** (code, config, migrations), and the likely root cause.

---

## Ruby (rbenv)

The Spree server requires the exact Ruby version in **`server/.ruby-version`**. Install it with rbenv:

```bash
# From repo root: install Ruby + ruby-build + bundler (non-interactive)
bash deploy/install_ruby.sh
```

Then load rbenv in your shell (add to `~/.bashrc` or `~/.profile`):

```bash
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"
```

Or install manually:

```bash
# 1. Install rbenv and ruby-build (see install_ruby.sh for apt dependencies)
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

# 2. Install the version required by the server
RUBY_VERSION=$(cat server/.ruby-version)
rbenv install -s "$RUBY_VERSION"
rbenv global "$RUBY_VERSION"
gem install bundler
```

---

## MySQL (database)

The Spree server uses **MySQL**. Set up MySQL and the app database:

```bash
bash deploy/install_mysql.sh
```

Then in `server/` run `bundle install` and `RAILS_ENV=production rails db:prepare`. Ensure `server/.env.production` has `RAILS_ENV=production`, `SECRET_KEY_BASE`, and `DB_ADAPTER=mysql2`.

---

## Environment and SECRET_KEY_BASE

Production needs `RAILS_ENV=production`, `SECRET_KEY_BASE`, and `DB_ADAPTER=mysql2`. A template lives in **`server/.env.production`**.

**Generate a secure SECRET_KEY_BASE** (once, then put it in `.env.production` or your systemd/env):

```bash
cd server && bundle exec rails secret
```

Or with OpenSSL:

```bash
openssl rand -hex 64
```

Replace the `SECRET_KEY_BASE=please_generate` placeholder in `server/.env.production` with the generated value. The systemd unit loads this file.

---

## How to run verification

From the **repository root**:

```bash
bash deploy/verify_deployment.sh
```

The script targets the Rails app in **`/server`** by default. Override with:

```bash
APP_DIR=/path/to/server RAILS_ENV=production bash deploy/verify_deployment.sh
```

No interactive input is required.

---

## Section-by-section failures

### RUNTIME

| Failure | Meaning | DevOps vs App | Root cause / fix |
|--------|--------|----------------|------------------|
| **Ruby not found** | `ruby` is not in PATH or not installed. | **DevOps** | Install the version in `server/.ruby-version` via rbenv: `bash deploy/install_ruby.sh`. Then ensure PATH includes `$HOME/.rbenv/shims`. |
| **Bundler not found** | `bundle` command missing. | **DevOps** | Run `gem install bundler` (after rbenv is active). Run `rbenv rehash` if needed. |
| **bundle install failed** | Dependencies could not be installed. | **App** (Gemfile/lock) or **DevOps** (network, native deps) | Check Gemfile/Gemfile.lock; run `bundle install` in `server/`. On Linux install dev headers (e.g. `default-libmysqlclient-dev`) if the `mysql2` gem fails to compile. |

---

### RAILS BOOT

| Failure | Meaning | DevOps vs App | Root cause / fix |
|--------|--------|----------------|------------------|
| **rails about failed** | Rails app does not boot. | **App** (config/load error) or **DevOps** (env) | Often missing `SECRET_KEY_BASE` or broken `config/application.rb` / initializers. Run `rails about` in `server/` and read the trace. |
| **rails routes failed** | Route drawing fails (e.g. constant missing, engine not loaded). | **App** | Check `config/routes.rb` and that Spree engines are mounted; run `rails routes` and fix the reported constant or route. |
| **rails zeitwerk:check failed** | Autoloading is broken (wrong file/constant names or load order). | **App** | Fix file names and constant names to match Zeitwerk conventions; ensure no references to constants before they are defined. |

---

### DATABASE

| Failure | Meaning | DevOps vs App | Root cause / fix |
|--------|--------|----------------|------------------|
| **MySQL not running** | MySQL service is stopped. | **DevOps** | Run `bash deploy/install_mysql.sh` or `sudo systemctl start mysql`. |
| **rails db:prepare failed** (connection) | Cannot connect to MySQL. | **DevOps** | Run `bash deploy/install_mysql.sh`; ensure `server/config/database.yml` credentials match (user `spree`, password `spree123`, host `127.0.0.1`). |
| **rails db:prepare failed** | DB does not exist or migrations cannot run. | **App** (migrations) or **DevOps** (connection) | Fix connection (see above); then run `rails db:create db:migrate` or `rails db:prepare` in `server/` and resolve migration errors. |
| **Pending migrations** | There are `down` migrations. | **App** (deploy step skipped) | Run `cd server && bundle exec rails db:migrate` (and restart the app if needed). |

---

### ASSETS

| Failure | Meaning | DevOps vs App | Root cause / fix |
|--------|--------|----------------|------------------|
| **assets:precompile failed** | Asset pipeline (e.g. Propshaft) or JS/CSS build failed. | **App** (manifest, node, or gems) or **DevOps** (missing node/yarn) | Run `rails assets:precompile` in `server/` and fix the reported error (missing asset, node command, or gem). |

---

### PUMA

| Failure | Meaning | DevOps vs App | Root cause / fix |
|--------|--------|----------------|------------------|
| **Socket file missing** | Puma is not bound to the expected unix socket path. | **DevOps** (path, permissions, or Puma not started with socket) | Create dir: `mkdir -p /var/www/spree/shared/tmp/sockets`. Start Puma with `-b unix:///var/www/spree/shared/tmp/sockets/puma.sock`. If under a different deploy path, set `SPREE_SHARED_PATH` or adjust `config/puma.rb`. |
| **Path exists but is not a socket** | A file was created instead of a socket (e.g. wrong Puma bind or stale file). | **DevOps** | Remove the file and restart Puma with the correct bind so it creates a real socket. |
| **No Puma process listening** | Puma is not running or crashed. | **DevOps** or **App** (boot crash) | Start Puma manually or via systemd; check logs (journalctl -u spree, or Puma stderr) for boot/crash errors. |

---

### SYSTEMD

| Failure | Meaning | DevOps vs App | Root cause / fix |
|--------|--------|----------------|------------------|
| **spree unit not found** | Unit file not installed. | **DevOps** | Copy unit: `sudo cp deploy/spree.service /etc/systemd/system/`, then `sudo systemctl daemon-reload`, `sudo systemctl enable --now spree`. |
| **spree service not active** | Unit exists but service is stopped or failed. | **DevOps** or **App** (exit on boot) | Run `sudo systemctl start spree`; if it fails, inspect `journalctl -u spree -n 50` and fix the reported error (path, env, or Rails boot). |

---

### NGINX

| Failure | Meaning | DevOps vs App | Root cause / fix |
|--------|--------|----------------|------------------|
| **nginx config invalid** | `nginx -t` fails. | **DevOps** | Fix the config (often under `/etc/nginx/sites-enabled/`); run `sudo nginx -t` and correct syntax or paths. |
| **curl localhost -> 502** | Nginx cannot talk to the app server. | **DevOps** | Puma is down or socket path is wrong. Ensure Puma is running and bound to the same socket path as in nginx `upstream` (e.g. `unix:///var/www/spree/shared/tmp/sockets/puma.sock`). |
| **curl localhost -> 404** | Nginx serves but app returns 404. | **App** (routing) or **DevOps** (wrong root/location) | Check Rails routes and that the app is mounted at `/`; check nginx `root` and `location /` proxy_pass. |
| **curl localhost -> 000** | Connection refused or no route. | **DevOps** | Nginx not running or not listening on 80: `sudo systemctl start nginx`. |

---

## Quick decision tree

1. **Rails won’t boot** (about/routes/zeitwerk) → **Application**: config, routes, autoload.
2. **DB connection / db:prepare / migrations** → **DevOps** for service and URL; **Application** for migration errors.
3. **Puma not listening / no socket** → **DevOps**: start Puma with correct bind and dirs; if it exits immediately, use logs to see if it’s an **App** boot error.
4. **502 from Nginx** → **DevOps**: Puma down or wrong socket path.
5. **200/302 from curl** → App and proxy are working.

---

## One-command check

On a new server, from the repo root:

```bash
bash deploy/verify_deployment.sh
```

Use the printed **FIX** lines and this README to decide whether the issue is **DevOps** (services, paths, env) or **Application** (Rails config, routes, migrations, code).
