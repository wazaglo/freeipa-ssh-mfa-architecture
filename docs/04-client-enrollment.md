# Phase 4: Client Enrollment

## Overview

A server is enrolled into FreeIPA, assigned to a host group, and Ansible automatically applies the correct SSH configuration based on that group. No manual config on the client.

## The Model

```
Enroll → Assign to host group → Ansible applies correct sshd_config
         ↓
Admin creates HBAC rule with specific hosts → Admin adds users to deployment group
```

The server's **host group** (`dev-servers`, `uat-servers`, `prod-servers`) determines which `AuthenticationMethods` it enforces on its SSH connection. This is configured via Ansible, not by hand.

**Important: Adding a server to a host group does NOT grant anyone access to it.** Host groups are only used by Ansible to discover servers and apply `sshd_config`. Authorization is handled separately via deployment group → specific host HBAC rules (see Phase 7).

## Enrollment Process

### 1. On the IPA Server: Pre-Create Host Entry (Optional)

```bash
kinit admin

ipa host-add prd01.devuatprod.com --ip-address=10.0.0.31
```

This is optional — `ipa-client-install` can auto-create the host entry on first enrollment.

### 2. On the Client: Install and Enroll

```bash
# Debian / Ubuntu
apt-get update && apt-get install -y ipa-client oddjob-mkhomedir sssd sssd-tools

# RHEL / CentOS
dnf install -y ipa-client oddjob-mkhomedir sssd sssd-tools

# Join the domain
ipa-client-install \
    --domain=devuatprod.com \
    --realm=DEVUATPROD.COM \
    --server=ipa.devuatprod.com \
    --mkhomedir \
    --force-join \
    --unattended
```

### 3. On the IPA Server: Assign to Host Group

```bash
kinit admin
ipa hostgroup-add-member prod-servers --hosts=prd01.devuatprod.com
```

### 4. Run Ansible to Apply Config

```bash
ansible-playbook -i ansible/inventory/prod.yml ansible/playbooks/enroll-clients.yml
```

Ansible will:
1. Detect which host group the server belongs to via FreeIPA
2. Apply the correct `sshd_config` (dev/uat/prod)
3. Configure SSSD with appropriate `pam_verbosity`
4. Enable SSH key distribution via `sss_ssh_authorizedkeys`
5. Restart services

## Zero-Manual-Config on Clients

After enrollment and Ansible run, the client should require zero manual intervention:

| What | How it's set |
|---|---|
| SSH auth method | `sshd_config` via Ansible (based on host group) |
| SSH key distribution | `sss_ssh_authorizedkeys` via Ansible |
| SSSD pam_verbosity | `/etc/sssd/sssd.conf` via Ansible |
| PAM stack | `pam_sss.so` configured during `ipa-client-install` |
| Home directory | `oddjobd-mkhomedir` auto-creates on first login |
| User/group info | SSSD resolves from FreeIPA LDAP |

## What Happens on Each Environment

| Host Group | `AuthenticationMethods` | `pam_verbosity` |
|---|---|---|
| `dev-servers` | `publickey` | `0` (no OTP prompts) |
| `uat-servers` | `publickey,password` | `0` (single password prompt) |
| `prod-servers` | `publickey,keyboard-interactive` | `1` (separate Password: / OTP: prompts) |

## Common Pitfalls / Real-World Notes

| Symptom | Cause | Fix |
|---|---|---|
| `ipa-client-install` hangs | DNS not resolving IPA server | Check `/etc/resolv.conf` |
| SSSD won't start | Bad config | `sssctl config-check` |
| Home dir not created | oddjobd not running | `systemctl enable --now oddjobd` |
| User gets `/bin/sh` not `/bin/bash` | IPA default shell | `ipa user-mod <user> --shell=/bin/bash` on IPA server, then `sss_cache -u <user>` on client |
| `sss_cache` not found | `sssd-tools` not installed | `apt-get install -y sssd-tools` |
| OTP prompt never appears (Password: loops) | PAM order wrong on Debian | Put `pam_sss.so forward_pass` FIRST in `common-auth` (see `configs/pam/common-auth-prod-debian`) |
| OTP token created but not prompted | User auth type not updated | `ipa user-mod <user> --user-auth-type=otp` |

## Post-Enrollment: Granting Access

After enrollment, the server is ready but **no one can SSH into it yet**. Access must be explicitly granted:

1. Add the specific host to a deployment's HBAC rule:
   ```bash
   ipa hbacrule-add-host crm-prod-access --hosts=prd01.devuatprod.com
   ```
2. Add users to the deployment group:
   ```bash
   ipa group-add-member crm-deployment --users=neymar
   ```

See [Phase 7: HBAC Policy](07-hbac-policy.md) for details.

## Next Steps

Proceed to [Phase 5: User and Group Creation Strategy](05-user-group-strategy.md).
