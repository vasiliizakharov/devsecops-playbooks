#!/usr/bin/env bash
#
# basic-auth-deployment.sh
#
# Deploy two-layer defence in front of a WordPress wp-admin:
#   Layer 1: nginx IP allowlist (allow <office-ip>; deny all;)
#   Layer 2: HTTP Basic-Auth inside the same location.
#
# Usage:
#   sudo ./basic-auth-deployment.sh <DOMAIN> <BASIC_AUTH_USER>
#
# Idempotent — re-running is safe.

set -euo pipefail

DOMAIN="${1:?usage: $0 <DOMAIN> <BASIC_AUTH_USER>}"
USER="${2:?usage: $0 <DOMAIN> <BASIC_AUTH_USER>}"

VHOST="/etc/nginx/sites-enabled/${DOMAIN}.conf"
HTPASSWD="/etc/nginx/htpasswd-${DOMAIN}"

# --- 1. Validate input -------------------------------------------------------

if [[ ! -r "$VHOST" ]]; then
  echo "ERROR: $VHOST not found or not readable." >&2
  exit 1
fi

if ! command -v htpasswd >/dev/null 2>&1; then
  echo "ERROR: htpasswd binary missing. apt-get install apache2-utils" >&2
  exit 1
fi

# --- 2. Create/update htpasswd file ------------------------------------------

if [[ ! -e "$HTPASSWD" ]]; then
  echo "Creating new $HTPASSWD for user '$USER'..."
  htpasswd -B -c "$HTPASSWD" "$USER"
else
  echo "Updating existing $HTPASSWD for user '$USER'..."
  htpasswd -B "$HTPASSWD" "$USER"
fi
chown root:www-data "$HTPASSWD"
chmod 0640 "$HTPASSWD"

# --- 3. Patch the vhost ------------------------------------------------------

# Look for an existing wp-admin location, otherwise insert one.
if grep -qE 'location ~?\* \^\?\/?\(wp-admin\|wp-login' "$VHOST"; then
  echo "wp-admin location already exists in $VHOST. Verify manually that it has the two-layer config."
else
  echo "Inserting wp-admin two-layer location into $VHOST..."

  cp "$VHOST" "${VHOST}.bak-pre-basic-auth-$(date -u +%Y%m%dT%H%M%SZ)"

  # Insert before the closing server } — naive but works for single-server vhosts.
  awk -v u="$USER" -v ht="$HTPASSWD" '
    /^}/ && !done {
      print "    # --- WP admin two-layer protection ---"
      print "    location ~ ^/(wp-admin|wp-login\\.php) {"
      print "        allow <OFFICE_IP_OR_CIDR>;"
      print "        deny all;"
      print ""
      print "        auth_basic           \"restricted\";"
      print "        auth_basic_user_file " ht ";"
      print ""
      print "        # Pass through to PHP after auth gate"
      print "        try_files $uri $uri/ /index.php?$args;"
      print "        location ~ \\.php$ {"
      print "            fastcgi_pass unix:/run/php/php8.1-fpm.sock;"
      print "            include fastcgi_params;"
      print "            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;"
      print "        }"
      print "    }"
      done=1
    }
    { print }
  ' "$VHOST" > "${VHOST}.new"

  mv "${VHOST}.new" "$VHOST"
fi

# --- 4. Validate and reload --------------------------------------------------

nginx -t

echo
echo "Now edit $VHOST and replace <OFFICE_IP_OR_CIDR> with your real allowlist."
echo "Then: systemctl reload nginx"
echo
echo "Verify:"
echo "  curl -I https://${DOMAIN}/wp-admin/    # expect 401 from off-office IP"
echo "  curl -I -u ${USER}:<pw> https://${DOMAIN}/wp-admin/   # expect 302/200"
