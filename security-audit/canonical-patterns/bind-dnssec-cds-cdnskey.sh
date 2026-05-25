#!/usr/bin/env bash
#
# bind-dnssec-cds-cdnskey.sh
#
# Canonical BIND 9.16+ inline-signing setup with CDS/CDNSKEY publication
# (RFC 8078: Managing DS Records from the Parent via CDS/CDNSKEY).
#
# Run as root on the master authoritative NS.
#
# After enabling, the parent registrar that supports RFC 8078 will pull your
# CDS/CDNSKEY records and update the DS at the parent automatically.
#
# Tested on Debian 12 / BIND 9.18.

set -euo pipefail

ZONE="${1:?usage: $0 <zone>}"            # e.g. example.com
KEY_DIR="/etc/bind/keys/${ZONE}"
ZONE_FILE="/etc/bind/db.${ZONE}"
NAMED_LOCAL="/etc/bind/named.conf.local"

# ---- 1. Key directory --------------------------------------------------------

install -d -m 0750 -o bind -g bind "$KEY_DIR"

# ---- 2. dnssec-policy snippet (named.conf.options) ---------------------------

if ! grep -q 'dnssec-policy "default"' /etc/bind/named.conf.options; then
  cat >>/etc/bind/named.conf.options <<'POLICY'

# RFC 8078-compatible default policy
dnssec-policy "default" {
    keys {
        ksk lifetime unlimited algorithm 13;     # ECDSAP256SHA256
        zsk lifetime P30D     algorithm 13;
    };
    publish-safety  PT1H;
    retire-safety   PT1H;
    parent-propagation-delay PT2H;
    cds-digest-types { 2; };                     # SHA-256 only
};
POLICY
fi

# ---- 3. Zone declaration -----------------------------------------------------

if ! grep -q "zone \"${ZONE}\"" "$NAMED_LOCAL"; then
  cat >>"$NAMED_LOCAL" <<ZONE_DECL

zone "${ZONE}" {
    type master;
    file "${ZONE_FILE}";
    key-directory "${KEY_DIR}";
    dnssec-policy "default";
    inline-signing yes;
    allow-transfer { <SLAVE_NS_ACL>; };          # tighten me
};
ZONE_DECL
fi

# ---- 4. Validate + reload ----------------------------------------------------

named-checkconf
named-checkzone "$ZONE" "$ZONE_FILE"
rndc reload "$ZONE"

# ---- 5. Verify CDS/CDNSKEY are being published -------------------------------

sleep 5   # let signer publish

echo "=== DNSKEY ==="
dig +noall +answer @127.0.0.1 "$ZONE" DNSKEY

echo "=== CDS ==="
dig +noall +answer @127.0.0.1 "$ZONE" CDS

echo "=== CDNSKEY ==="
dig +noall +answer @127.0.0.1 "$ZONE" CDNSKEY

cat <<NEXT

Next steps:
  1. Wait for CDS/CDNSKEY to propagate to your secondary NS (TTL-dependent).
  2. If your registrar supports RFC 8078 auto-pull, DS will be added at the
     parent automatically within hours-to-days (registrar-dependent).
  3. If not, copy the DS record manually:
       dig +noall +answer @127.0.0.1 "$ZONE" DS
     and paste into your registrar's DS panel.
  4. Validate end-to-end:
       dig +dnssec @8.8.8.8 "$ZONE" SOA | grep -E '(RRSIG|flags: qr rd ra ad)'
     The 'ad' flag means external validators trust your chain.

NEXT
