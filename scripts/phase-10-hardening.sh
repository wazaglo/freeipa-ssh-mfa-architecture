#!/bin/bash
# Phase 10: Hardening and Troubleshooting
# Run this on ALL servers (IPA server and clients)
set -euo pipefail

IPA_DOMAIN="devuatprod.com"

echo "[+] Phase 10: Hardening and Security Configuration"

# ==========================================
# 1. SELinux (RHEL/CentOS only — skip on Debian)
# ==========================================
echo ""
echo "=== 1. SELinux ==="
if command -v getenforce &>/dev/null; then
    if [[ "$(getenforce)" != "Enforcing" ]]; then
        echo "[!] SELinux is not enforcing. Setting to enforcing..."
        setenforce 1
        sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    fi
    echo "[ ] SELinux: $(getenforce)"
else
    echo "[ ] SELinux: not applicable (non-RHEL system)"
fi

# ==========================================
# 2. Firewall (ensure only required ports open)
# ==========================================
echo ""
echo "=== 2. Firewall Configuration ==="
if command -v firewall-cmd &>/dev/null; then
    systemctl enable --now firewalld

    # On IPA server
    if hostname -f | grep -q "ipa"; then
        firewall-cmd --set-default-zone=public
        firewall-cmd --permanent --add-service=freeipa-ldap
        firewall-cmd --permanent --add-service=freeipa-ldaps
        firewall-cmd --permanent --add-service=dns
        firewall-cmd --permanent --add-service=ntp
        firewall-cmd --permanent --add-service=kerberos
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --remove-service=dhcp 2>/dev/null || true
        firewall-cmd --permanent --remove-service=dhcpv6 2>/dev/null || true
        echo "[ ] IPA server firewall rules applied."
    else
        firewall-cmd --set-default-zone=public
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --remove-service=dhcp 2>/dev/null || true
        firewall-cmd --permanent --remove-service=dhcpv6 2>/dev/null || true
        echo "[ ] Client firewall rules applied (SSH-only inbound)."
    fi
    firewall-cmd --reload
else
    echo "[ ] firewalld not available (Debian). Configure UFW or iptables manually."
fi

# ==========================================
# 3. SSH Hardening (verify current config)
# ==========================================
echo ""
echo "=== 3. SSH Hardening Verification ==="
echo "[ ] Checking critical SSH settings..."

SSH_CHECKS=(
    "PermitRootLogin no"
    "MaxAuthTries 3"
    "X11Forwarding no"
    "UsePAM yes"
    "GSSAPIAuthentication yes"
)

for check in "${SSH_CHECKS[@]}"; do
    KEY=$(echo "$check" | awk '{print $1}')
    EXPECTED=$(echo "$check" | awk '{print $2}')
    ACTUAL=$(sshd -T 2>/dev/null | grep -i "^$KEY " | awk '{print $2}')
    if [[ "$ACTUAL" == "$EXPECTED" ]]; then
        echo "  ✅ $KEY = $ACTUAL"
    else
        echo "  ❌ $KEY = ${ACTUAL:-NOT SET} (expected: $EXPECTED)"
    fi
done

# ==========================================
# 4. SSSD and Kerberos Verification
# ==========================================
echo ""
echo "=== 4. SSSD and Kerberos ==="
systemctl is-active sssd >/dev/null 2>&1 && \
    echo "  ✅ SSSD running" || \
    echo "  ❌ SSSD not running"

sssctl domain-status "$IPA_DOMAIN" 2>/dev/null || echo "  [!] sssctl not available"

klist -s 2>/dev/null && \
    echo "  ✅ Valid Kerberos ticket exists" || \
    echo "  ⚠️  No Kerberos ticket (kinit admin to obtain)"

# ==========================================
# 5. Audit Logging (use package module for cross-distro)
# ==========================================
echo ""
echo "=== 5. Audit Configuration ==="
if command -v apt-get &>/dev/null; then
    apt-get install -y auditd
else
    dnf install -y auditd
fi
systemctl enable --now auditd

# Add audit rules for authentication monitoring
cat > /etc/audit/rules.d/auth-monitoring.rules << 'AUDIT_RULES'
-w /etc/ssh/sshd_config -p wa -k ssh_config
-w /etc/ssh/sshd_config.d/ -p wa -k ssh_config
-w /etc/pam.d/ -p wa -k pam_config
-w /etc/sssd/ -p wa -k sssd_config
-w /var/log/secure -p wa -k auth_log
-w /var/log/messages -p wa -k syslog
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
AUDIT_RULES

augenrules --load
echo "  ✅ Audit rules loaded"

# ==========================================
# 6. Troubleshooting Diagnostics
# ==========================================
echo ""
echo "=== 6. Troubleshooting Diagnostics ==="
echo ""
cat << TROUBLE
FreeIPA Troubleshooting Commands:
----------------------------------
Auth issues:
  journalctl -u sshd -n 50 --no-pager
  tail -f /var/log/auth.log     (Debian)
  tail -f /var/log/secure       (RHEL)
  tail -f /var/log/sssd/sssd.log
  sssctl domain-status $IPA_DOMAIN

PAM/OTP issues (Debian PROD):
  grep pam_sss /etc/pam.d/common-auth
  cat /etc/pam.d/sshd-otp       (custom SSH PAM service with OTP)

PAM/OTP issues (RHEL PROD):
  grep pam_sss /etc/pam.d/system-auth
  grep pam_sss /etc/pam.d/password-auth

HBAC issues:
  ipa hbac-test --user=USER --host=HOST --service=sshd
  ipa hbacrule-find
  ipa group-find --users=USER

SSH key issues:
  sss_ssh_authorizedkeys USER
  ipa user-show USER --all | grep sshpubkey

Kerberos issues:
  klist
  kinit -V USER
  kvno host/HOSTNAME

DNS issues:
  dig +short ipa.$IPA_DOMAIN
  dig +short -x <IP>
  dig SRV _kerberos._tcp.$IPA_DOMAIN
TROUBLE

echo ""
echo "[+] Phase 10 complete."
echo "[ ] System hardened. See troubleshooting guide above."
echo ""
echo "========================================="
echo "  FreeIPA SSH MFA Architecture"
echo "  Implementation Complete!"
echo "========================================="