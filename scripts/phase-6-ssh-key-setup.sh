#!/bin/bash
# Phase 6: SSH Integration and Key Management
# Run on IPA server to upload keys for users
set -euo pipefail

echo "[+] Phase 6: SSH Key Management"
echo ""
echo "Options:"
echo "  1) Admin uploads SSH public key for a user"
echo "  2) User uploads their own SSH public key"
echo "  3) Verify key distribution"
echo ""

read -rp "Choose option (1-3): " OPTION

case "$OPTION" in
    1)
        # Admin upload
        read -rp "Username: " USERNAME
        read -rp "Path to SSH public key file: " KEYFILE

        if [[ ! -f "$KEYFILE" ]]; then
            echo "[!] Key file not found: $KEYFILE"
            exit 1
        fi

        PUBKEY=$(cat "$KEYFILE")
        kinit admin
        ipa user-mod "$USERNAME" --sshpubkey="$PUBKEY"
        echo "[+] SSH key uploaded for $USERNAME"
        ;;

    2)
        # Self-service upload
        read -rp "Your username: " USERNAME
        read -rp "Path to your SSH public key: " KEYFILE

        if [[ ! -f "$KEYFILE" ]]; then
            echo "[!] Key file not found: $KEYFILE"
            exit 1
        fi

        PUBKEY=$(cat "$KEYFILE")
        kinit "$USERNAME"
        ipa user-mod "$USERNAME" --sshpubkey="$PUBKEY"
        echo "[+] SSH key uploaded. You can now log in with your key."
        ;;

    3)
        # Verify key distribution
        read -rp "Username to verify: " USERNAME

        echo ""
        echo "=== Key stored in FreeIPA ==="
        ipa user-show "$USERNAME" --all | grep "SSH public key"

        echo ""
        echo "=== Key available via SSSD on THIS server ==="
        /usr/bin/sss_ssh_authorizedkeys "$USERNAME" 2>/dev/null || echo "[!] No keys found or user not found"

        echo ""
        echo "=== Test login locally ==="
        echo "To test: ssh $USERNAME@localhost"
        ;;

    *)
        echo "[!] Invalid option"
        exit 1
        ;;
esac

echo ""
echo "[+] Phase 6 complete."
echo "[+] Next: Phase 7 - HBAC Policy Design"