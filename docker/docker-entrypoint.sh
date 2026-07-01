#!/bin/bash
set -e

export KRB5CCNAME=FILE:/tmp/krb5cc_0

IPA_SERVER="${IPA_SERVER:-ipa.test.local}"
IPA_DOMAIN="${IPA_DOMAIN:-test.local}"
IPA_REALM="${IPA_REALM:-TEST.LOCAL}"
ADMIN_PASS="${ADMIN_PASS:-admin123}"

# Join IPA domain if not already joined
if [ ! -f /etc/ipa/ca.crt ]; then
    /usr/sbin/ipa-client-install \
        --domain="$IPA_DOMAIN" \
        --realm="$IPA_REALM" \
        --server="$IPA_SERVER" \
        --mkhomedir \
        --force-join \
        --unattended \
        -p admin \
        -w "$ADMIN_PASS" \
        --no-ntp \
        &>/dev/null || true
fi

# Ensure FILE-based credential cache (KEYRING does not work without systemd)
if ! grep -q "default_ccache_name = FILE:" /etc/krb5.conf.d/default-realm 2>/dev/null; then
    mkdir -p /etc/krb5.conf.d
    printf "[libdefaults]\n    default_realm = TEST.LOCAL\n    default_ccache_name = FILE:/tmp/krb5cc_%%{uid}\n" > /etc/krb5.conf.d/default-realm
fi

# Start services
/usr/sbin/sshd
# oddjobd and sssd cannot use systemctl in containers, so start them directly
oddjobd --start &>/dev/null || true
/usr/sbin/sssd -D --logger=files &>/dev/null || true

# Keep container running
exec tail -f /dev/null
