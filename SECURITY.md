# Security Considerations

This repository contains a reference architecture for FreeIPA SSH MFA. Before deploying in any environment, review the following advisories and complete the mandatory checklist.

## Mandatory Pre-Deployment Checklist

### Credentials and Secrets

- **Never use default passwords.** Shell scripts use hardcoded defaults (e.g., `DEFAULT_PASS="password"`). Set `IPA_ADMIN_PASSWORD` and `IPA_DM_PASSWORD` environment variables before running any script.
- **Never commit credentials.** The `.gitignore` excludes `secrets/ipa-admin-creds.env`, but always verify before pushing.
- **Use Ansible Vault** for all password management in Ansible playbooks. Do not store passwords in plaintext variables or files.
- **Rotate the IPA admin and Directory Manager passwords** immediately after initial installation.
- **Configure a FreeIPA password policy** after installation:
  ```bash
  kinit admin
  ipa pwpolicy-add --minlength=12 --minclasses=3 --maxlife=90 --minlife=1 --history=5 --lockout=true --lockouttime=300 globalPolicy
  ```

### Infrastructure

- **Replace all example values.** This repository uses `devuatprod.com`, `10.0.0.x` IPs, and specific hostnames from a test deployment. Change every occurrence before production use.
- **Use LDAPS (port 636)** for all LDAP communication. The LDIF examples reference plain LDAP (port 389) — do not use unencrypted LDAP in production.
- **Pre-distribute SSH host keys** via Ansible or configuration management. Do not rely on `StrictHostKeyChecking=accept-new` in production.

### PAM Configuration

- **Remove `nullok`** from all PAM configurations. This flag allows users with empty passwords to authenticate. Every PAM file in `configs/pam/` and the Ansible enrollment playbook contains `nullok`.

### SSSD Configuration

- **Set `krb5_store_password_if_offline = false`** in all SSSD configs. When set to `true`, SSSD caches user passwords on disk for offline authentication. If a client is compromised, cached credentials can be extracted. All three SSSD config files (`sssd-dev.conf`, `sssd-uat.conf`, `sssd-prod.conf`) currently have this set to `true`.

### SSH Configuration

- **Remove `GSSAPIAuthentication yes`** if Kerberos SSO is not required. This is enabled in all SSH configs and templates but may not be needed, expanding the attack surface unnecessarily.
- **Remove deprecated directives.** `Protocol 2` and `ChallengeResponseAuthentication` are deprecated in modern OpenSSH. Use `KbdInteractiveAuthentication` only.
- **Add `LoginGraceTime 30`** to all SSH configs. The default 120 seconds is overly generous for key-based auth.

### Password Expiration

- **Remove `--setattr=krbPasswordExpiration="20301231235959Z"`** from `scripts/phase-5-create-users.sh`. This sets user passwords to never expire. Let FreeIPA's password policy manage expiration.

## Known Issues in This Repository

The following security issues exist in the current codebase. They are documented here for transparency. Fix them before any production deployment.

| Severity | Issue | Location |
|----------|-------|----------|
| **CRITICAL** | Hardcoded password `DEFAULT_PASS="password"` echoed to stdout | `scripts/phase-5-create-users.sh:37,112` |
| **CRITICAL** | Admin and DM passwords printed to stdout and written to `/root/` | `scripts/phase-2-install-ipa-server.sh:28-31` |
| **CRITICAL** | Admin password visible in `/proc` via shell heredoc `kinit admin <<< "..."` | `ansible/roles/hbac/tasks/main.yml:3` |
| **HIGH** | Real infrastructure exposed: domain, IPs, hostnames hardcoded in ~187 locations | Entire repository |
| **HIGH** | `nullok` in PAM configs allows empty-password authentication | 8 files, 13 occurrences |
| **HIGH** | SSSD caches passwords on disk (`krb5_store_password_if_offline = true`) | All 3 SSSD config files |
| **HIGH** | Ansible reads password from plaintext file without `no_log: true` | `ansible/playbooks/enroll-clients.yml:9` |
| **HIGH** | `StrictHostKeyChecking=accept-new` enables MITM on first connection | `scripts/phase-9-test-auth.sh` |
| **MEDIUM** | Passwords set to never expire (2030) | `scripts/phase-5-create-users.sh:101` |
| **MEDIUM** | No Ansible Vault usage — all secrets in plaintext | All Ansible files |
| **MEDIUM** | LDIF example uses unencrypted LDAP (port 389) | `configs/ipa/hbac-rules.ldif:14` |
| **MEDIUM** | No FreeIPA password policy configured | Repository-wide |
| **LOW** | Deprecated `ChallengeResponseAuthentication` alongside `KbdInteractiveAuthentication` | 4 SSH config files |

## Network Security

- Restrict SSH access to authorized networks via firewall rules (firewalld, UFW, or iptables).
- Use FreeIPA's HBAC rules to enforce per-host access control — do not rely solely on network-level restrictions.
- Enable audit logging for authentication events (configured by `scripts/phase-10-hardening.sh`).
- Review audit logs regularly:
  ```bash
  ausearch -k ssh_config --start today
  ausearch -k auth_log --start today
  ```

## OTP / MFA

- OTP tokens in the Ansible role (`ansible/roles/otp-mfa/tasks/main.yml`) use a fixed expiry date. Update for dynamic expiry based on your rotation policy.
- Users must add TOTP secrets to their authenticator app (Google Authenticator, FreeOTP, etc.) after token creation.
- The OTP example secret `JBSWY3DPEHPK3PXP` in `docs/08-otp-mfa.md` is a well-known placeholder. Do not use it in production.

## Vulnerability Reporting

If you discover a security vulnerability in this repository, please open a GitHub issue with the `security` label. Do not disclose vulnerabilities publicly until a fix is available.
