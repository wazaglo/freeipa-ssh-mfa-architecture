#!/bin/bash
# Phase 5: User and Group Creation Strategy (Deployment Groups)
# Run this on the IPA server
set -euo pipefail

IPA_DOMAIN="devuatprod.com"
IPA_REALM="DEVUATPROD.COM"

echo "[+] Phase 5: User and Group Creation"
echo "[ ] Using Deployment Groups (not env-based user groups)"
kinit admin

# ==========================================
# Create Host Groups (Ansible use only — NOT for HBAC)
# ==========================================
echo ""
echo "=== Creating Host Groups (Ansible sshd_config targeting only) ==="
ipa hostgroup-add dev-servers --desc="DEV environment servers" || true
ipa hostgroup-add uat-servers --desc="UAT environment servers" || true
ipa hostgroup-add prod-servers --desc="PRODUCTION environment servers" || true

# ==========================================
# Create Deployment Groups (for HBAC authorization)
# ==========================================
echo ""
echo "=== Creating Deployment Groups ==="
ipa group-add crm-deployment --desc="CRM project team" --nonposix || true
ipa group-add erp-deployment --desc="ERP project team" --nonposix || true
ipa group-add monitoring --desc="Monitoring team" --nonposix || true
ipa group-add devops --desc="DevOps engineers (all environments)" --nonposix || true

# ==========================================
# Create Users
# ==========================================
echo ""
echo "=== Creating Users ==="
DEFAULT_PASS="password"

# Users assigned to deployment groups, NOT env user groups

ipa user-add jackson \
    --first=Jackson --last=Dev \
    --email=jackson@devuatprod.com \
    --title="Developer" \
    --displayname="Jackson Dev" \
    --shell=/bin/bash \
    --homedir=/home/jackson \
    --noprivate || true
ipa group-add-member erp-deployment --users=jackson || true

ipa user-add mbappe \
    --first=Kylian --last=Mbappe \
    --email=mbappe@devuatprod.com \
    --title="QA Engineer" \
    --displayname="Kylian Mbappe" \
    --shell=/bin/bash \
    --homedir=/home/mbappe \
    --noprivate || true
ipa group-add-member erp-deployment --users=mbappe || true

ipa user-add neymar \
    --first=Neymar --last=Jr \
    --email=neymar@devuatprod.com \
    --title="Production Engineer" \
    --displayname="Neymar Jr" \
    --shell=/bin/bash \
    --homedir=/home/neymar \
    --noprivate || true
ipa group-add-member crm-deployment --users=neymar || true
ipa group-add-member monitoring --users=neymar || true

ipa user-add john \
    --first=John --last=Doe \
    --email=john@devuatprod.com \
    --title="Senior Engineer" \
    --displayname="John Doe" \
    --shell=/bin/bash \
    --homedir=/home/john \
    --noprivate || true
ipa group-add-member crm-deployment --users=john || true

ipa user-add doe \
    --first=Jane --last=Doe \
    --email=doe@devuatprod.com \
    --title="DevOps Engineer" \
    --displayname="Jane Doe" \
    --shell=/bin/bash \
    --homedir=/home/doe \
    --noprivate || true
ipa group-add-member devops --users=doe || true
ipa group-add-member monitoring --users=doe || true

# ==========================================
# Set initial passwords
# ==========================================
echo ""
echo "=== Setting Initial Passwords ==="
for user in jackson mbappe neymar john doe; do
    echo "[+] Setting password for $user"
    echo "$DEFAULT_PASS" | ipa passwd "$user" --password="$DEFAULT_PASS" || true
    ipa user-mod "$user" --setattr=krbPasswordExpiration="20301231235959Z" || true
done

echo ""
echo "=== Summary ==="
ipa group-find
ipa hostgroup-find
ipa user-find

echo ""
echo "[+] Phase 5 complete."
echo "[ ] Default password for all users: $DEFAULT_PASS"
echo "[ ] Users are in deployment groups. Create HBAC rules next (Phase 7)."
echo "[+] Next: Phase 6 - SSH Integration and Key Management"
