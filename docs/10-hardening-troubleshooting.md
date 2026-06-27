# Phase 10: Hardening and Troubleshooting

## Security Hardening

### 1. SELinux (RHEL/CentOS)

Ensure SELinux is enforcing on ALL RHEL-based servers:

```bash
# Check status
getenforce

# Set enforcing (if not already)
setenforce 1
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config

# Check for denials
ausearch -m avc -ts recent
```

Debian systems do not use SELinux (AppArmor is the equivalent).

### 2. Firewall Configuration

#### IPA Server (RHEL):
```bash
firewall-cmd --set-default-zone=public
for svc in freeipa-ldap freeipa-ldaps dns ntp kerberos ssh http https; do
    firewall-cmd --permanent --add-service=$svc
done
firewall-cmd --reload
```

#### Clients:
```bash
firewall-cmd --set-default-zone=public
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --remove-service=dhcp 2>/dev/null || true
firewall-cmd --reload
```

#### Debian Clients (UFW):
```bash
ufw allow ssh
ufw enable
```

### 3. SSH Hardening

Applied via the environment-specific configs. Common rules for all:

```bash
grep -E "^(PermitRootLogin|MaxAuthTries|Protocol|X11Forwarding)" /etc/ssh/sshd_config
# Expected:
#   PermitRootLogin no
#   MaxAuthTries 3
#   Protocol 2
#   X11Forwarding no
```

Verify with:
```bash
sshd -T | grep -E "(permitrootlogin|maxauthtries|protocol|x11forwarding)"
```

### 4. PAM Lockout Configuration

On RHEL servers, configure account lockout:

```bash
# /etc/security/faillock.conf
cat > /etc/security/faillock.conf << 'EOF'
deny = 5
unlock_time = 900
fail_interval = 900
even_deny_root
EOF
```

### 5. Audit Logging

```bash
# Install auditd (use apt on Debian, dnf on RHEL)
if command -v apt-get &>/dev/null; then
    apt-get install -y auditd
else
    dnf install -y auditd
fi
systemctl enable --now auditd

# Authentication monitoring rules
cat > /etc/audit/rules.d/auth-monitoring.rules << 'EOF'
-w /etc/ssh/sshd_config -p wa -k ssh_config
-w /etc/pam.d/ -p wa -k pam_config
-w /etc/sssd/ -p wa -k sssd_config
-w /var/log/secure -p wa -k auth_log
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
EOF

augenrules --load
ausearch -k auth_log -ts today
```

### 6. Certificate Management

```bash
# Check IPA certificate status
ipa cert-show 1

# List all certificates
getcert list

# Monitor certificate expiry (add to cron)
ipa cert-find --status=VALID --all | grep "Not After"
```

### 7. Backup Strategy

```bash
# Full IPA backup
ipa-backup --online --data

# List backups
ipa-backup-list

# Scheduled backup (add to cron)
echo "0 2 * * * root /usr/sbin/ipa-backup --online --data --logs" > /etc/cron.d/ipa-backup
```

## Troubleshooting Guide

### Authentication Issues

| Symptom | Debug Command | Likely Fix |
|---|---|---|
| SSH hangs at auth | `journalctl -u sshd -n 50` | Check DNS resolution |
| Permission denied (publickey) | `ssh -vvv user@host` | Key not in IPA: `ipa user-show --all` |
| "No matching key found" | `/usr/bin/sss_ssh_authorizedkeys user` | SSSD `ssh` service missing from sssd.conf |
| Password prompt but fails | `kinit user` on client | Password expired or wrong |
| OTP prompt not appearing | `grep AuthenticationMethods /etc/ssh/sshd_config` | Wrong auth method in sshd_config |
| OTP always invalid | `chronyc tracking` on IPA server | Clock skew > 30 seconds |
| "Access denied by HBAC" | `ipa hbac-test --user= --host= --service=sshd` | User not in correct group |
| Sudo prompts for OTP | PAM service leak | `sudo` must use `common-auth`, not `sshd-otp` |

### PAM-Specific Issues

#### Platform: RHEL
```bash
# Check PAM auth order
grep pam_sss /etc/pam.d/system-auth
grep pam_sss /etc/pam.d/password-auth

# Expected for PROD (pam_sss.so forward_pass before pam_unix.so):
#   auth        sufficient    pam_sss.so forward_pass
#   auth        requisite     pam_deny.so
```

#### Platform: Debian
```bash
# Check SSH PAM service
cat /etc/pam.d/sshd-otp

# Check common-auth (used by sudo)
cat /etc/pam.d/common-auth

# Expected: sssd-otp has pam_sss.so forward_pass FIRST
# Expected: common-auth has pam_unix.so first, pam_sss.so use_first_pass
```

### SSSD Issues

```bash
# Check SSSD status
sssctl domain-status devuatprod.com

# Clear cache and restart
sss_cache -E
systemctl restart sssd

# Debug SSSD
systemctl stop sssd
sssd -d 5 --logger=stderr
```

### Kerberos Issues

```bash
# Check tickets
klist

# Test authentication
kinit -V user

# Check time sync (KDC requires <5 min skew)
chronyc tracking | grep "System time"

# Force time sync
chronyc -a makestep
```

### DNS Issues

```bash
# Test resolution
dig +short ipa.devuatprod.com

# Test reverse
dig +short -x 10.0.0.47

# Test SRV records
dig +short SRV _kerberos._tcp.devuatprod.com

# Check /etc/resolv.conf
cat /etc/resolv.conf
```

### Common Fixes

**Fix 1: Host key mismatch**
```bash
ssh-keygen -R hostname
```

**Fix 2: Re-enroll client**
```bash
ipa-client-install --uninstall
ipa-client-install --domain=devuatprod.com --realm=DEVUATPROD.COM --server=ipa.devuatprod.com
```

**Fix 3: Force SSSD key refresh**
```bash
sss_cache -u username
systemctl restart sssd
/usr/bin/sss_ssh_authorizedkeys username
```

### Monitoring

```bash
# Watch auth logs in real-time
tail -f /var/log/secure | grep -E "sshd|pam_sss|sudo"

# Failed login summary
grep "Failed password" /var/log/secure | awk '{print $9}' | sort | uniq -c | sort -rn

# HBAC denial summary
grep "hbac.*denied" /var/log/secure | awk '{print $14}' | sort | uniq -c | sort -rn
```

## Maintenance Tasks

### Weekly
```bash
# Check IPA replica status
ipa status

# Verify backups
ipa-backup-list
```

### Monthly
```bash
# Full system update (RHEL)
dnf update -y

# Full system update (Debian)
apt-get update && apt-get upgrade -y

# Review audit logs
aureport --failed --summary -ts -30day

# Verify HBAC rules
ipa hbacrule-find
```

### Quarterly
```bash
# Test disaster recovery
# Restore from backup: ipa-restore FILENAME

# Review user access
ipa user-find --all
```

## Next Steps

The implementation is complete. Review the architecture summary in [Phase 1](01-architecture-design.md) for the full picture.
