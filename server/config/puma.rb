# Puma config for systemd socket deployment
# Used when running under deploy/spree.service

workers 2
threads 5, 5
environment "production"
preload_app!

directory "/var/www/spree/current/server"

bind "unix:///var/www/spree/shared/tmp/sockets/puma.sock"

pidfile "/var/www/spree/shared/tmp/pids/puma.pid"

stdout_redirect "/var/www/spree/shared/log/puma.stdout.log",
                "/var/www/spree/shared/log/puma.stderr.log",
                true

activate_control_app

plugin :tmp_restart
