# Production Puma config for Capistrano deploy
# Bind/pid/log use shared dir: /var/www/spree/shared
# For local boot use: RAILS_ENV=production bundle exec rails s (listens on port)

workers ENV.fetch("WEB_CONCURRENCY", 2)
threads 5, 5

shared_path = ENV.fetch("SPREE_SHARED_PATH", "/var/www/spree/shared")

bind "unix://#{shared_path}/tmp/sockets/puma.sock"
pidfile "#{shared_path}/tmp/pids/puma.pid"
state_path "#{shared_path}/tmp/pids/puma.state"

stdout_redirect "#{shared_path}/log/puma_stdout.log", "#{shared_path}/log/puma_stderr.log", true

plugin :tmp_restart
