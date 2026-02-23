#!/usr/bin/env bash
#
# Verify production deployment health.
# Run on server. Exits 0 only if all checks pass.

set +e

FAIL=0

# MySQL running
if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mysqld 2>/dev/null; then
  echo "PASS: mysql running"
else
  echo "FAIL: mysql not running"
  FAIL=1
fi

# Puma socket exists
if [[ -S /var/www/spree/shared/tmp/sockets/puma.sock ]]; then
  echo "PASS: puma socket exists"
else
  echo "FAIL: puma socket missing"
  FAIL=1
fi

# systemd spree active
if systemctl is-active --quiet spree 2>/dev/null; then
  echo "PASS: systemd spree active"
else
  echo "FAIL: systemd spree not active"
  FAIL=1
fi

# nginx active
if systemctl is-active --quiet nginx 2>/dev/null; then
  echo "PASS: nginx active"
else
  echo "FAIL: nginx not active"
  FAIL=1
fi

# curl localhost returns 200
CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null)
if [[ "$CODE" == "200" ]] || [[ "$CODE" == "302" ]]; then
  echo "PASS: curl localhost -> $CODE"
else
  echo "FAIL: curl localhost -> $CODE"
  FAIL=1
fi

exit $FAIL
