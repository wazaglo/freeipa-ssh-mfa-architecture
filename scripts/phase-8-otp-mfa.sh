#!/bin/bash
# Phase 8: MFA (OTP) Implementation for Production
# Run this on the IPA server
set -euo pipefail

echo "[+] Phase 8: MFA (OTP) Implementation for Production"
echo ""
echo "This script creates OTP tokens for PROD users."
echo "Users must have an OTP authenticator app (Google Auth, FreeOTP, etc.)"
echo ""

read -rp "Proceed? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Aborted."
    exit 0
fi

kinit admin

# ==========================================
# Create OTP tokens for production users
# ==========================================
echo ""
echo "=== Creating OTP Tokens ==="

# List of users requiring OTP (production access)
PROD_USERS="neymar john doe"

for user in $PROD_USERS; do
    echo ""
    echo "[+] Creating TOTP token for $user..."

    # Create TOTP token (time-based, 30-second interval)
    TOKEN_URI=$(ipa otptoken-add \
        --type=totp \
        --owner="$user" \
        --desc="Production OTP Token for $user" \
        --digits=6 \
        --interval=30 \
        --qrcount=1 \
        --not-after="$(date -d '+365 days' +'%Y%m%d%H%M%S')Z" \
        "$user-prod-otp" \
        --all 2>/dev/null)

    if [[ $? -eq 0 ]]; then
        echo "[+] OTP token created for $user"
        echo "[ ] Token URI: $TOKEN_URI"
        echo "[ ] User should scan the QR code in their authenticator app"
        ipa otptoken-show "$user-prod-otp" --all | grep "uri"
    else
        echo "[!] Failed to create OTP token for $user. May already exist."
        ipa otptoken-find --owner="$user" 2>/dev/null || true
    fi

    # Set user auth type to OTP (required for PROD login)
    echo "[+] Setting user-auth-type=otp for $user..."
    ipa user-mod "$user" --user-auth-type=otp
done

# ==========================================
# Apply KDC OTP plugin config on IPA server
# ==========================================
echo ""
echo "=== Applying KDC OTP Plugin on IPA Server ==="
cat > /etc/krb5.conf.d/ipa-otp.conf << 'KRB5_OTP'
# FreeIPA KDC OTP pre-authentication plugin configuration
# Restart KDC after adding: systemctl restart krb5kdc

[kdcpreauth]
    otp = {
        module = otp:/usr/lib64/krb5/plugins/preauth/otp.so
    }
KRB5_OTP

systemctl restart krb5kdc
echo "[+] KDC OTP plugin configured and KDC restarted"

# ==========================================
# Verify OTP tokens
# ==========================================
echo ""
echo "=== OTP Token Summary ==="
ipa otptoken-find

echo ""
echo ""
echo "[+] Phase 8 complete."
echo "[ ] OTP tokens created for production users."
echo "[ ] Users must add the TOTP secret to their authenticator app."
echo "[+] Next: Phase 9 - Testing Authentication Flows"