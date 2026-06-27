#!/bin/bash
# Phase 3: Domain Setup, DNS, and Kerberos Realm Configuration
# Run on the IPA server after successful installation
set -euo pipefail

IPA_DOMAIN="devuatprod.com"
IPA_REALM="DEVUATPROD.COM"

echo "[+] Phase 3: Domain, DNS, and Kerberos Verification"

# Authenticate as admin
kinit admin

echo ""
echo "=== DNS Zone ==="
ipa dnszone-find

echo ""
echo "=== DNS Records ==="
dig +short SOA "$IPA_DOMAIN"
dig +short SRV _kerberos._tcp."$IPA_DOMAIN"
dig +short SRV _kerberos._udp."$IPA_DOMAIN"
dig +short SRV _ldap._tcp."$IPA_DOMAIN"
dig +short SRV _kpasswd._tcp."$IPA_DOMAIN"
dig +short SRV _ntp._udp."$IPA_DOMAIN"

echo ""
echo "=== Kerberos Verification ==="
klist
kvno host/"$(hostname -f)"

echo ""
echo "=== Test DNS Forward Resolution ==="
dig +short "$(hostname -f)"
dig +short -x "$(hostname -I | awk '{print $1}')"

echo ""
echo "=== IPA Topology ==="
ipa topologysegment-find

echo ""
echo "=== Certificate Authority ==="
ipa cert-show 1

echo ""
echo "=== Create DNS reverse zone if missing ==="
IP_CIDR=$(hostname -I | awk '{print $1}' | awk -F. '{print $1"."$2"."$3}')
REVERSE_ZONE="${IP_CIDR//./}.in-addr.arpa."
ipa dnszone-find "$REVERSE_ZONE" 2>/dev/null || {
    echo "[+] Creating reverse zone $REVERSE_ZONE"
    ipa dnszone-add "$REVERSE_ZONE"
}

echo ""
echo "=== Summary ==="
echo "Domain  : $IPA_DOMAIN"
echo "Realm   : $IPA_REALM"
echo "KDC     : $(hostname -f)"
echo "DNS     : Integrated (IPA-managed)"
echo "CA      : IPA Internal CA (Dogtag)"
echo ""
echo "[+] Phase 3 complete."
echo "[+] Next: Phase 4 - Client Enrollment"