#!/bin/bash
# Phase 7: HBAC Policy — Deployment Groups → Specific Hosts
# Run this on the IPA server
set -euo pipefail

echo "[+] Phase 7: HBAC Policy — Deployment Groups to Specific Hosts"
echo ""
echo "This script creates HBAC rules that map deployment groups"
echo "to specific individual hosts (not host groups)."
echo ""
echo "WARNING: This replaces the old env-based (dev-access, uat-access, prod-access) model."
echo ""

read -rp "Proceed? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Aborted."
    exit 0
fi

kinit admin

# ==========================================
# Disable default allow_all rule first
# ==========================================
echo ""
echo "[+] Disabling default allow_all rule (forces explicit HBAC)..."
ipa hbacrule-disable allow_all 2>/dev/null || true

# ==========================================
# Remove old env-based rules if they exist
# ==========================================
echo ""
echo "[+] Removing old env-based HBAC rules (if present)..."
for old_rule in dev-access uat-access prod-access; do
    ipa hbacrule-del "$old_rule" 2>/dev/null || true
done

# ==========================================
# Create deployment-based HBAC rules
# Each rule maps a deployment group to SPECIFIC HOSTS
# ==========================================

# --- CRM Deployment ---
echo ""
echo "[+] Creating CRM deployment rules..."

# CRM: DEV
ipa hbacrule-add crm-dev-access \
    --desc="CRM team access DEV server" || true
ipa hbacrule-add-user crm-dev-access \
    --groups=crm-deployment || true
ipa hbacrule-add-host crm-dev-access \
    --hosts=dev01.devuatprod.com || true
ipa hbacrule-add-service crm-dev-access \
    --services=sshd || true

# CRM: UAT
ipa hbacrule-add crm-uat-access \
    --desc="CRM team access UAT server" || true
ipa hbacrule-add-user crm-uat-access \
    --groups=crm-deployment || true
ipa hbacrule-add-host crm-uat-access \
    --hosts=uat01.devuatprod.com || true
ipa hbacrule-add-service crm-uat-access \
    --services=sshd || true

# CRM: PROD (two specific hosts)
ipa hbacrule-add crm-prod-access \
    --desc="CRM team access PROD servers" || true
ipa hbacrule-add-user crm-prod-access \
    --groups=crm-deployment || true
ipa hbacrule-add-host crm-prod-access \
    --hosts=prd01.devuatprod.com || true
ipa hbacrule-add-host crm-prod-access \
    --hosts=prd02.devuatprod.com || true
ipa hbacrule-add-service crm-prod-access \
    --services=sshd || true

# --- ERP Deployment ---
echo ""
echo "[+] Creating ERP deployment rules..."

ipa hbacrule-add erp-all-access \
    --desc="ERP team access all environments" || true
ipa hbacrule-add-user erp-all-access \
    --groups=erp-deployment || true
ipa hbacrule-add-host erp-all-access \
    --hosts=dev02.devuatprod.com || true
ipa hbacrule-add-host erp-all-access \
    --hosts=uat02.devuatprod.com || true
ipa hbacrule-add-host erp-all-access \
    --hosts=prd03.devuatprod.com || true
ipa hbacrule-add-host erp-all-access \
    --hosts=prd04.devuatprod.com || true
ipa hbacrule-add-service erp-all-access \
    --services=sshd || true

# --- Monitoring ---
echo ""
echo "[+] Creating Monitoring deployment rules..."

ipa hbacrule-add monitoring-access \
    --desc="Monitoring team access PROD servers" || true
ipa hbacrule-add-user monitoring-access \
    --groups=monitoring || true
for host in prd01 prd02 prd03 prd04 prd05; do
    ipa hbacrule-add-host monitoring-access \
        --hosts="${host}.devuatprod.com" || true
done
ipa hbacrule-add-service monitoring-access \
    --services=sshd || true

# --- DevOps All-Access (exception — uses host groups) ---
echo ""
echo "[+] Creating DevOps all-access rule..."
ipa hbacrule-add devops-all-access \
    --desc="DevOps engineers can access all environments via SSH" || true
ipa hbacrule-add-user devops-all-access \
    --groups=devops || true
ipa hbacrule-add-host devops-all-access \
    --hostgroups=dev-servers || true
ipa hbacrule-add-host devops-all-access \
    --hostgroups=uat-servers || true
ipa hbacrule-add-host devops-all-access \
    --hostgroups=prod-servers || true
ipa hbacrule-add-service devops-all-access \
    --services=sshd || true

# ==========================================
# List all HBAC rules
# ==========================================
echo ""
echo "=== HBAC Rules Summary ==="
ipa hbacrule-find

# ==========================================
# Test HBAC rules
# ==========================================
echo ""
echo "=== Testing HBAC Rules ==="
echo "Test: Can neymar (CRM) access prd01?"
ipa hbac-test --user=neymar --host=prd01.devuatprod.com --service=sshd 2>/dev/null || true

echo ""
echo "Test: Can neymar (CRM) access prd03? (should be DENIED)"
ipa hbac-test --user=neymar --host=prd03.devuatprod.com --service=sshd 2>/dev/null || true

echo ""
echo "Test: Can mbappe (ERP) access dev02?"
ipa hbac-test --user=mbappe --host=dev02.devuatprod.com --service=sshd 2>/dev/null || true

echo ""
echo "Test: Can jackson (ERP) access dev01? (should be DENIED)"
ipa hbac-test --user=jackson --host=dev01.devuatprod.com --service=sshd 2>/dev/null || true

echo ""
echo "Test: Can doe (DevOps) access all servers?"
ipa hbac-test --user=doe --host=prd01.devuatprod.com --service=sshd 2>/dev/null || true
ipa hbac-test --user=doe --host=dev01.devuatprod.com --service=sshd 2>/dev/null || true

echo ""
echo "[+] Phase 7 complete."
echo "[ ] HBAC rules use deployment groups → specific hosts."
echo "[ ] Adding a server to a host group does NOT grant access."
echo "[+] Next: Phase 8 - MFA (OTP) for Production"
