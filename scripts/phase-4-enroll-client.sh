#!/bin/bash
# Phase 4: Client Enrollment (DEV, UAT, PROD)
# Run this on EACH client server
# Usage: ./phase-4-enroll-client.sh <dev|uat|prod>
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <dev|uat|prod> [ipa_server_ip]"
    echo "  dev  — DEV environment (key-only auth)"
    echo "  uat  — UAT environment (key+password auth)"
    echo "  prod — PRODUCTION environment (key+password+OTP auth)"
    exit 1
fi

ENV="$1"
IPA_SERVER_IP="${2:-10.0.0.47}"
IPA_DOMAIN="devuatprod.com"
IPA_REALM="DEVUATPROD.COM"

echo "[+] Phase 4: Client Enrollment"
echo "[ ] Environment: $ENV"
echo "[ ] IPA Server: $IPA_SERVER_IP"

# Verify hostname is FQDN
HOSTNAME_FQDN=$(hostname -f)
if [[ "$HOSTNAME_FQDN" != *"$IPA_DOMAIN" ]]; then
    echo "[!] Hostname must be FQDN (e.g., ${ENV}01.$IPA_DOMAIN)"
    echo "[!] Current: $HOSTNAME_FQDN"
    exit 1
fi

# Install IPA client packages
if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get install -y ipa-client oddjob-mkhomedir sssd sssd-tools
else
    dnf install -y ipa-client oddjob-mkhomedir sssd sssd-tools
fi

# Join IPA domain
ipa-client-install \
    --domain="$IPA_DOMAIN" \
    --realm="$IPA_REALM" \
    --server="ipa.$IPA_DOMAIN" \
    --ip-address="$IPA_SERVER_IP" \
    --enable-dns-updates \
    --mkhomedir \
    --force-join \
    --unattended

# Enable oddjobd for mkhomedir
systemctl enable --now oddjobd

# Restart services (Ansible will apply the correct SSH/SSSD config)
systemctl restart sssd
systemctl restart sshd

# Test IPA connectivity
echo "[+] Testing connectivity..."
ipa user-find admin 2>/dev/null || echo "[!] ipa command failed — check sssd logs"

# Check SSSD status
sssctl domain-status "$IPA_DOMAIN"

echo ""
echo "[+] Phase 4 complete for $HOSTNAME_FQDN ($ENV)."
echo "[ ] Client enrolled. Run Ansible playbook to apply SSH/SSSD config:"
echo "    ansible-playbook -i ansible/inventory/${ENV}.yml ansible/playbooks/enroll-clients.yml"
echo "[+] Next: Phase 5 - User and Group Creation"