#!/bin/bash
# Phase 2: FreeIPA Server Installation
# Run this on the IPA server ONLY
set -euo pipefail

IPA_SERVER="ipa.devuatprod.com"
IPA_DOMAIN="devuatprod.com"
IPA_REALM="DEVUATPROD.COM"
IPA_ADMIN_PASSWORD="${IPA_ADMIN_PASSWORD:-$(openssl rand -base64 24)}"
IPA_DM_PASSWORD="${IPA_DM_PASSWORD:-$(openssl rand -base64 24)}"

echo "[+] Phase 2: FreeIPA Server Installation"
echo "[ ] Server: $IPA_SERVER"
echo "[ ] Domain: $IPA_DOMAIN"
echo "[ ] Realm: $IPA_REALM"

# Verify hostname
if [[ "$(hostname -f)" != "$IPA_SERVER" ]]; then
    echo "[!] Hostname mismatch. Expected: $IPA_SERVER, Got: $(hostname -f)"
    exit 1
fi

# Enable IDM module and install FreeIPA with DNS
dnf module enable -y idm:DL1
dnf install -y @idm:DL1 ipa-server ipa-server-dns

# Backup existing passwords
echo "$IPA_ADMIN_PASSWORD" > /root/.ipa_admin_pass
echo "$IPA_DM_PASSWORD" > /root/.ipa_dm_pass
chmod 600 /root/.ipa_admin_pass /root/.ipa_dm_pass

# Run IPA server installer
ipa-server-install \
    --setup-dns \
    --auto-forwarders \
    --auto-reverse \
    --ds-password="$IPA_DM_PASSWORD" \
    --admin-password="$IPA_ADMIN_PASSWORD" \
    --domain="$IPA_DOMAIN" \
    --realm="$IPA_REALM" \
    --hostname="$IPA_SERVER" \
    --ip-address="$(hostname -I | awk '{print $1}')" \
    --mkhomedir \
    --unattended

# Verify installation
echo "[+] Verifying installation..."
kinit admin <<< "$IPA_ADMIN_PASSWORD"
ipa user-find admin

# Check DNS
dig +short SOA "$IPA_DOMAIN"
dig +short SRV _kerberos._tcp."$IPA_DOMAIN"
dig +short SRV _ldap._tcp."$IPA_DOMAIN"

# Create IPA admin RC file for convenience
cat > /root/.ipa_env.sh << 'EOF'
export IPA_DOMAIN="devuatprod.com"
export IPA_REALM="DEVUATPROD.COM"
export IPA_SERVER="ipa.devuatprod.com"
EOF
chmod +x /root/.ipa_env.sh

echo "[+] Phase 2 complete."
echo "[ ] Admin password saved to /root/.ipa_admin_pass"
echo "[ ] DM password saved to /root/.ipa_dm_pass"
echo "[+] Next: Phase 3 - Domain, DNS, and Kerberos Configuration"