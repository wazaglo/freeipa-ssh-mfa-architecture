# Phase 8: MFA (OTP) Implementation for Production

## Overview

FreeIPA provides native OTP (One-Time Password) support using TOTP (Time-based One-Time Password) as defined in RFC 6238. Production servers require SSH key + password + OTP for authentication.

**Important:** OTP only applies to SSH authentication, not sudo. See PAM Separation section below.

## Authentication Flow on PROD

```
Step 1: SSH public key verification
  Client presents SSH key → SSH daemon validates via SSSD
  └─► /usr/bin/sss_ssh_authorizedkeys fetches user's keys from IPA
  └─► If key matches → Step 2
  └─► If no match → Connection closed

Step 2: PAM via sshd-otp service (separate prompts)
  SSH uses custom PAM service "sshd-otp" (not common-auth)
  → pam_sss.so forward_pass → SSSD → FreeIPA KDC

  Prompt 1: "Password: "        ←─ user enters their IPA password
  Prompt 2: "OTP: "             ←─ user enters 6-digit TOTP code

  KDC validates both → Access granted
```

**sudo** uses `common-auth` (standard PAM stack without OTP) — only password required.

## 1. Enable OTP Authentication Type for User

Before creating tokens, the user must have OTP as their authentication type:

```bash
kinit admin
ipa user-mod neymar --user-auth-type=otp
```

Without this, the KDC never requests OTP from the user.

## 2. Create OTP Tokens for Production Users

```bash
kinit admin

# For each production user, create a TOTP token
ipa otptoken-add \
    --type=totp \
    --owner=neymar \
    --desc="Production OTP Token for neymar" \
    --digits=6 \
    --interval=30 \
    --not-after="2027-01-01 00:00:00" \
    neymar-prod-otp

ipa otptoken-add \
    --type=totp \
    --owner=john \
    --desc="Production OTP Token for john" \
    --digits=6 \
    --interval=30 \
    --not-after="2027-01-01 00:00:00" \
    john-prod-otp
```

**Note:** Tokens can also be created via the FreeIPA Web UI at `https://ipa.devuatprod.com/ipa/ui` → Authentication → OTP Tokens → Add.

## 3. Distribute OTP Secrets to Users

After token creation, the URI containing the TOTP secret is displayed:

```bash
# Show OTP token URI (contains the secret key)
ipa otptoken-show neymar-prod-otp --all | grep uri

# Output example:
# uri: otpauth://totp/DEVUATPROD.COM:neymar?secret=JBSWY3DPEHPK3PXP&issuer=DEVUATPROD.COM&algorithm=SHA1&digits=6&period=30
```

Users can add this to their authenticator app by:
- **Option A:** Scanning a QR code (use `qrencode` to generate from URI)
- **Option B:** Manually entering the secret from the URI
- **Option C:** Using the FreeIPA self-service web UI (`https://ipa.devuatprod.com/ipa/ui`)

## 4. PAM Separation: SSH vs Sudo

### The Problem

On Debian, both `sshd` and `sudo` include `@include common-auth`. If common-auth has `pam_sss.so forward_pass` first (needed for OTP), then sudo would also prompt for OTP — undesirable.

### The Fix: Dedicated PAM Service for SSH

Create `/etc/pam.d/sshd-otp` — only used for SSH:

```bash
# /etc/pam.d/sshd-otp
#%PAM-1.0
auth    [success=2 default=ignore]      pam_sss.so forward_pass
auth    [success=1 default=ignore]      pam_unix.so
auth    requisite                       pam_deny.so
auth    required                        pam_permit.so
auth    optional                        pam_cap.so
@include common-account
@include common-session-noninteractive
```

Configure sshd to use this service in `/etc/ssh/sshd_config`:

```
PAMService sshd-otp
```

### common-auth stays standard for sudo:

```bash
# /etc/pam.d/common-auth  (standard, no OTP!)
auth    [success=2 default=ignore]  pam_unix.so
auth    [success=1 default=ignore]  pam_sss.so use_first_pass
auth    requisite                   pam_deny.so
auth    required                    pam_permit.so
auth    optional                    pam_cap.so
```

This way:
- **SSH login** 🡒 uses `sshd-otp` PAM service 🡒 key + password + OTP
- **sudo** 🡒 uses `common-auth` 🡒 password only (no OTP)

## 5. Verify PROD SSH Config

```bash
grep -E "AuthenticationMethods|KbdInteractive|PAMService" /etc/ssh/sshd_config
# Expected:
#   AuthenticationMethods publickey,keyboard-interactive
#   KbdInteractiveAuthentication yes
#   PAMService sshd-otp
```

## 6. Verify OTP Token Status

```bash
# List all OTP tokens
ipa otptoken-find

# Show specific token details
ipa otptoken-show neymar-prod-otp --all

# Check token owner
ipa otptoken-find --owner=neymar
```

## 7. KDC OTP Plugin Configuration

If the KDC logs don't show the OTP plugin loading, create:

```bash
# /etc/krb5.conf.d/ipa-otp.conf
[kdcpreauth]
    otp = {
        module = otp:/usr/lib64/krb5/plugins/preauth/otp.so
    }
```

Then restart the KDC:
```bash
systemctl restart krb5kdc
```

Verify it loads:
```bash
journalctl -u krb5kdc --no-pager | grep -i "otp\|loaded\|plugin"
```

## 8. Testing OTP Authentication

```bash
# From a workstation, attempt SSH to PROD server
ssh -i ~/.ssh/id_ed25519 neymar@prd01.devuatprod.com

# Expected prompt sequence:
#   Password: <enter password>
#   OTP: <enter 6-digit TOTP code from authenticator app>
```

## Troubleshooting OTP

| Symptom | Cause | Fix |
|---|---|---|
| No OTP prompt | `AuthenticationMethods` wrong | Should be `publickey,keyboard-interactive` |
| "Invalid OTP" | Clock skew | Check `chronyc tracking` on IPA server and client |
| OTP not accepted | Wrong seed | Re-create token: `ipa otptoken-del` then `ipa otptoken-add` |
| Single prompt instead of two | PAM verbosity too low | Set `pam_verbosity = 1` in `sssd.conf` |
| Token expired | Token lifetime exceeded | Create token with longer `--not-after` |
| Password prompt loops (no OTP) | PAM auth order wrong on Debian | `pam_sss.so` must come **before** `pam_unix.so` in sshd-otp |
| `tokeninfo_matches: Unsupported authtok type 1` | `pam_unix.so` collects password first | PAM order wrong (see Debian fix above) |
| OTP plugin not loaded in KDC | Missing `kdcpreauth` config | Add `/etc/krb5.conf.d/ipa-otp.conf` |
| OTP prompt also appears for sudo | Wrong PAM service file | `sudo` must NOT use `sshd-otp` PAM service |
| Sudo asks for OTP | common-auth has forward_pass | Keep common-auth standard (pam_unix first, pam_sss use_first_pass) |

## Next Steps

Proceed to [Phase 9: Testing Authentication Flows](09-testing-auth-flows.md).
