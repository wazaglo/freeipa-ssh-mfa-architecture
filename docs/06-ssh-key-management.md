# Phase 6: SSH Integration and Key Management

## Overview

SSH public keys are stored centrally in FreeIPA and distributed to clients via SSSD. No manual key copying is needed.

## Key Distribution Pipeline

```
User uploads key to IPA     IPA stores key in LDAP     SSSD fetches key
       │                           │                         │
       ▼                           ▼                         ▼
┌──────────────┐         ┌──────────────────┐       ┌─────────────────┐
│ ipa user-mod │ ──────► │ cn=mbappe,cn=... │ ────► │ sss_ssh_author- │
│ --sshpubkey  │         │ dc=devuatprod,.. │       │ izedkeys mbappe │
└──────────────┘         └──────────────────┘       └────────┬────────┘
                                                              │
                                                              ▼
                                                     ┌─────────────────┐
                                                     │ SSH Authorized- │
                                                     │ KeysCommand     │
                                                     └─────────────────┘
```

## 1. User-Generated SSH Key Pair

Users generate an Ed25519 key pair on their workstation:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "mbappe@laptop"
```

## 2. Upload Key to FreeIPA

### Option A: Admin uploads for users

```bash
kinit admin
ipa user-mod mbappe --sshpubkey="$(cat ~/.ssh/id_ed25519.pub)"
```

### Option B: User self-service (after password change)

```bash
kinit mbappe  # authenticate as the user
ipa user-mod mbappe --sshpubkey="$(cat ~/.ssh/id_ed25519.pub)"
```

### Option C: Multi-key support

```bash
ipa user-mod mbappe \
    --sshpubkey="ssh-ed25519 AAAAC3... mbappe@laptop" \
    --sshpubkey="ssh-ed25519 AAAAD4... mbappe@desktop"
```

## 3. Verify Key Storage

```bash
ipa user-show mbappe --all | grep "SSH public key"
```

## 4. Client-Side Key Distribution

SSSD provides the `ssh` service for key distribution. Verify configuration:

### `/etc/sssd/sssd.conf` must include `ssh` in services:

```ini
[sssd]
services = nss, pam, ssh
```

### `/etc/ssh/sshd_config.d/ipa-keys.conf`:

```
AuthorizedKeysCommand /usr/bin/sss_ssh_authorizedkeys
AuthorizedKeysCommandUser nobody
```

### Test key retrieval:

```bash
# As root
/usr/bin/sss_ssh_authorizedkeys mbappe

# Should output the public key(s) stored in IPA
```

## 5. SSH Client Configuration (Users)

Users should configure their SSH client:

```bash
cat >> ~/.ssh/config << 'EOF'
# DEV - key only
Host *.dev.devuatprod.com
    PreferredAuthentications publickey
    IdentityFile ~/.ssh/id_ed25519

# UAT - key + password
Host *.uat.devuatprod.com
    PreferredAuthentications publickey,password
    IdentityFile ~/.ssh/id_ed25519

# PROD - key + keyboard-interactive (password + OTP)
Host *.prd.devuatprod.com
    PreferredAuthentications publickey,keyboard-interactive
    IdentityFile ~/.ssh/id_ed25519

# Default
Host ipa.devuatprod.com
    GSSAPIAuthentication yes
    GSSAPIDelegateCredentials yes
EOF
```

## 6. Key Rotation Policy

```bash
# List all users with their SSH keys
ipa user-find --all | grep -E "User login:|SSH public key"

# Force key rotation for a user
kinit admin
ipa user-mod mbappe --sshpubkey=""                    # Clear old keys
ipa user-mod mbappe --sshpubkey="ssh-ed25519 NEWKEY..."  # Add new key
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `sss_ssh_authorizedkeys` returns nothing | SSH service not in SSSD | Add `ssh` to `services` in sssd.conf |
| Keys not showing after upload | Cache stale | `sss_cache -u mbappe` or `systemctl restart sssd` |
| Permission denied (publickey) | Key not matching | Verify with `ssh -v` debug output |
| Multiple keys returned | All keys attempted | SSH tries each key automatically |

## Next Steps

Proceed to [Phase 7: HBAC Policy Design](07-hbac-policy.md).
