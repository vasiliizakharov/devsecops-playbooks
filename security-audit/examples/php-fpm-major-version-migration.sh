#!/usr/bin/env bash
#
# php-fpm-major-version-migration.sh
#
# Move a single site from PHP-FPM 7.4 to PHP-FPM 8.1 with zero-downtime,
# using two side-by-side pools and an atomic nginx flip.
#
# Usage:
#   sudo ./php-fpm-major-version-migration.sh <DOMAIN> <APP_USER>
#
# Pre-flight checks:
#   * Both php7.4-fpm AND php8.1-fpm packages installed.
#   * Site code already passes static analysis on PHP 8.1 (phpcs/psalm/etc).
#   * Functional smoke test plan ready.

set -euo pipefail

DOMAIN="${1:?usage: $0 <DOMAIN> <APP_USER>}"
APP_USER="${2:?usage: $0 <DOMAIN> <APP_USER>}"

OLD_POOL="/etc/php/7.4/fpm/pool.d/${APP_USER}.conf"
NEW_POOL="/etc/php/8.1/fpm/pool.d/${APP_USER}.conf"
VHOST="/etc/nginx/sites-enabled/${DOMAIN}.conf"

# --- 0. Sanity ---------------------------------------------------------------

[[ -r "$OLD_POOL" ]] || { echo "Old pool $OLD_POOL not found."; exit 1; }
[[ -r "$VHOST"   ]] || { echo "Vhost $VHOST not found."; exit 1; }

# --- 1. Create the new pool, mirror of the old one ---------------------------

if [[ -e "$NEW_POOL" ]]; then
  echo "New pool already exists: $NEW_POOL. Skipping creation."
else
  echo "Mirroring old pool into PHP 8.1 location..."
  cp "$OLD_POOL" "$NEW_POOL"

  # Most pools reference a socket path that includes the PHP version — fix it.
  sed -i 's|/run/php/php7\.4-fpm-|/run/php/php8.1-fpm-|g' "$NEW_POOL"
  sed -i 's|/var/log/php7\.4-fpm|/var/log/php8.1-fpm|g'   "$NEW_POOL"
fi

# --- 2. Validate and start the new pool --------------------------------------

php-fpm8.1 -t
systemctl restart php8.1-fpm

# --- 3. Verify the new socket exists -----------------------------------------

NEW_SOCK="/run/php/php8.1-fpm-${APP_USER}.sock"
if [[ ! -S "$NEW_SOCK" ]]; then
  echo "ERROR: expected socket $NEW_SOCK not present. Check /etc/php/8.1/fpm/pool.d/${APP_USER}.conf 'listen' directive." >&2
  exit 1
fi

# --- 4. Run a smoke test BEFORE flipping nginx -------------------------------

cat <<SMOKE
=== SMOKE TEST PRE-FLIP ===

The new pool is now running but no traffic is hitting it yet. To test, point a
*staging* vhost at the new socket and run your functional suite. Only after
the suite passes should you continue to step 5.

When ready, press Enter to flip nginx.
SMOKE
read -r

# --- 5. Atomic flip in nginx -------------------------------------------------

OLD_SOCK="/run/php/php7.4-fpm-${APP_USER}.sock"
TS=$(date -u +%Y%m%dT%H%M%SZ)

cp "$VHOST" "${VHOST}.bak-pre-php81-${TS}"

sed -i "s|fastcgi_pass unix:${OLD_SOCK};|fastcgi_pass unix:${NEW_SOCK};|g" "$VHOST"

nginx -t
systemctl reload nginx     # graceful — does not kill workers

echo "Flipped. Now run your functional suite again against the production URL."

# --- 6. Keep old pool warm for 7 days ----------------------------------------

cat <<NEXT

The old pool is still running and will continue to do so. Plan to disable it
after 7 quiet days:

    systemctl stop php7.4-fpm
    systemctl disable php7.4-fpm
    apt-mark hold php7.4-fpm   # do not auto-remove

Rollback is fast: revert the vhost from the backup and reload nginx.

    cp "${VHOST}.bak-pre-php81-${TS}" "$VHOST"
    systemctl reload nginx
NEXT
