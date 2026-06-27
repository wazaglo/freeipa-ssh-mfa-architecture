# Phase 9: Testing Authentication Flows for All Environments

## Test Matrix

| Test Case | DEV | UAT | PROD |
|-----------|-----|-----|------|
| Key only | ✅ Expected: Success | ❌ Expected: Denied | ❌ Expected: Denied |
| Key + password | ❌ Not tested (no password auth) | ✅ Expected: Success | ❌ Expected: Missing OTP |
| Key + password + OTP | ❌ Not tested | ❌ Not tested | ✅ Expected: Success |
| No key | ❌ Expected: Denied | ❌ Expected: Denied | ❌ Expected: Denied |
| Wrong password | ❌ Not applicable | ❌ Expected: Denied | ❌ Expected: Denied |
| Wrong OTP | ❌ Not applicable | ❌ Not applicable | ❌ Expected: Denied |
| HBAC denied | ❌ Expected: Denied (crm user → erp host) | ❌ Expected: Denied (erp user → crm host) | ❌ Expected: Denied (host not in deployment rule) |

## Test 1: DEV — Key-Only Authentication

```bash
# Should SUCCEED (key only, no password prompt)
ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey \
    -o StrictHostKeyChecking=accept-new \
    -o BatchMode=yes \
    jackson@dev02.devuatprod.com "hostname; whoami"

# Expected: hostname and username printed, no password prompt

# Should FAIL (password auth disabled on DEV)
ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=password \
    -o PasswordAuthentication=yes \
    -o BatchMode=no \
    jackson@dev02.devuatprod.com "echo success"

# Expected: "Permission denied (publickey)"
```

## Test 2: UAT — Key + Password Authentication

```bash
# Interactive test
ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey,password \
    mbappe@uat02.devuatprod.com "hostname; whoami"

# Expected flow:
#   1. SSH key verified (silent)
#   2. Password prompt: "mbappe@uat02.devuatprod.com's password:"
#   3. Enter password → authenticated
```

## Test 3: PROD — Key + Password + OTP

```bash
# Interactive test
ssh -i ~/.ssh/id_ed25519 \
    -o PreferredAuthentications=publickey,keyboard-interactive \
    neymar@prd01.devuatprod.com "hostname; whoami"

# Expected flow:
#   1. SSH key verified (silent)
#   2. Password prompt: "Password:"
#   3. OTP prompt: "OTP:"
#   4. Both verified → authenticated

# Test without OTP (should fail)
ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey,password \
    neymar@prd01.devuatprod.com "echo success"
# Should fail because password-only auth is not allowed
```

## Test 4: HBAC — Granular Access Control

```bash
# CRM user (neymar) can access prd01 (in crm-prod-access rule)
ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey,keyboard-interactive \
    neymar@prd01.devuatprod.com "echo 'CRM PROD access OK'"

# CRM user (neymar) trying prd03 (NOT in crm-prod-access) — should be denied
ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey \
    -o BatchMode=yes \
    neymar@prd03.devuatprod.com "echo success"
# Expected: "shell access denied" or session closed immediately

# ERP user (mbappe) can access prd03 (in erp-all-access rule)
ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey,keyboard-interactive \
    mbappe@prd03.devuatprod.com "echo 'ERP PROD access OK'"

# ERP user (mbappe) trying prd01 (NOT in erp-all-access) — should be denied
ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey \
    -o BatchMode=yes \
    mbappe@prd01.devuatprod.com "echo success"
# Expected: "shell access denied"
```

## Test 5: Cross-Environment User Access

```bash
# CRM user has access to dev01, uat01, prd01, prd02
ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey \
    -o BatchMode=yes \
    john@dev01.devuatprod.com "echo 'DEV CRM access OK'"

ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey,password \
    john@uat01.devuatprod.com "echo 'UAT CRM access OK'"

ssh -i ~/.ssh/id_ed25519 \
    -o PreferredAuthentications=publickey,keyboard-interactive \
    john@prd01.devuatprod.com "echo 'PROD CRM access OK'"

# but NOT server outside CRM deployment
ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey \
    -o BatchMode=yes \
    john@prd03.devuatprod.com "echo success"
# Expected: denied
```

## Test 6: DevOps All-Environment Access

```bash
# Doe is in devops group (all-access override)
ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey \
    doe@dev01.devuatprod.com "echo 'DEV access OK'"

ssh -i ~/.ssh/id_ed25519 -o PreferredAuthentications=publickey,password \
    doe@uat01.devuatprod.com "echo 'UAT access OK'"

ssh -i ~/.ssh/id_ed25519 \
    -o PreferredAuthentications=publickey,keyboard-interactive \
    doe@prd01.devuatprod.com "echo 'PROD access OK'"
```

## Test 7: Kerberos Ticket-Based Authentication (Optional)

```bash
# Obtain Kerberos ticket
kinit doe

# SSH with GSSAPI (no password if ticket valid)
ssh -o GSSAPIAuthentication=yes \
    -o PreferredAuthentications=gssapi-keyex,gssapi-with-mic \
    doe@prd01.devuatprod.com "klist"
```

## Automated Test Suite

Use the script `scripts/phase-9-test-auth.sh` for semi-automated testing:

```bash
./scripts/phase-9-test-auth.sh
```

## Log Verification

After each test, verify the logs:

```bash
# On the target server
journalctl -u sshd -n 20 --no-pager | grep "Accepted\|Failed"
tail -5 /var/log/secure        # RHEL
tail -5 /var/log/auth.log      # Debian

# On the IPA server (for HBAC checks)
journalctl -u sssd -n 20 --no-pager | grep -i hbac
grep -i "hbac.*denied" /var/log/secure
```

## Expected Log Outputs

**Successful PROD login:**
```
sshd[12345]: Accepted publickey for neymar from 10.0.0.50 port 54321 ssh2: ED25519 SHA256:...
sshd[12345]: pam_sss(sshd-otp:auth): authentication success; logname= uid=0 euid=0 tty=ssh ruser= rhost=10.0.0.50 user=neymar
sshd[12345]: Accepted keyboard-interactive/pam for neymar from 10.0.0.50 port 54321 ssh2
sshd[12345]: pam_unix(sshd-otp:session): session opened for user neymar
```

**HBAC denied login:**
```
sshd[12346]: pam_sss(sshd:account): Access denied for user jackson: 6 (Permission denied)
sshd[12346]: fatal: Access denied for user jackson by PAM account configuration
```

## Next Steps

Proceed to [Phase 10: Hardening and Troubleshooting](10-hardening-troubleshooting.md).
