#!/bin/bash
# Phase 1: Architecture Design and Prerequisites
# Run this on ALL servers (IPA server and clients)
set -euo pipefail

IPA_DOMAIN="devuatprod.com"
IPA_SERVER="ipa.devuatprod.com"

echo "[+] Phase 1: Prerequisites Check"

# Detect OS
if grep -qi "debian\|ubuntu" /etc/os-release 2>/dev/null; then
    OS_FAMILY="Debian"
elif grep -qi "centos\|red hat\|rocky\|alma" /etc/os-release 2>/dev/null; then
    OS_FAMILY="RHEL"
else
    OS_FAMILY="unknown"
fi
echo "[ ] OS: $OS_FAMILY"

# Set hostname (customize per server)
# IPA server: hostnamectl set-hostname ipa.devuatprod.com
# DEV client: hostnamectl set-hostname dev01.devuatprod.com
# UAT client: hostnamectl set-hostname uat01.devuatprod.com
# PROD client: hostnamectl set-hostname prd01.devuatprod.com
echo "[ ] Ensure FQDN hostname is set. Current: $(hostname -f)"

# Configure chronyd NTP (RHEL) or ntp/chrony (Debian)
if [[ "$OS_FAMILY" == "Debian" ]]; then
    apt-get update -qq && apt-get install -y chrony || true
else
    dnf install -y chrony
fi
systemctl enable --now chronyd 2>/dev/null || systemctl enable --now chrony 2>/dev/null || true
chronyc sources -v

# Ensure /etc/hosts is clean (no duplicate entries for IPA domain)
echo "[ ] Verify /etc/hosts does not have conflicting entries"

# Update system
if [[ "$OS_FAMILY" == "Debian" ]]; then
    apt-get update -qq && apt-get upgrade -y
else
    dnf update -y
fi

# Install required base packages
if [[ "$OS_FAMILY" == "Debian" ]]; then
    apt-get install -y vim wget curl dnsutils
else
    dnf install -y firewalld vim wget curl net-tools bind-utils
fi

echo ""
echo "[+] Phase 1 complete. Reboot recommended before proceeding."
echo "[+] Next: Phase 2 - FreeIPA Server Installation"