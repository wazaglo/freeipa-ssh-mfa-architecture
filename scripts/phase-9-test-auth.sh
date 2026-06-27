#!/bin/bash
# Phase 9: Testing Authentication Flows for All Environments
# Tests deployment-group-based HBAC (per-host, not per-host-group)
# Run this from any client or workstation with SSH access
set -euo pipefail

IPA_DOMAIN="devuatprod.com"

echo "========================================="
echo "  Authentication Flow Test Suite"
echo "  FreeIPA SSH MFA Architecture"
echo "  Deployment Groups → Specific Hosts"
echo "========================================="
echo ""

# ==========================================
# Test Configuration
# ==========================================
CRM_USER="neymar"
ERP_USER="mbappe"
DEVOPS_USER="doe"

# CRM deployment has access to: dev01, uat01, prd01, prd02
# ERP deployment has access to: dev02, uat02, prd03, prd04
# Monitoring has access to:     all prod servers
# Devops has access to:         all servers

CRM_DEV_HOST="dev01.$IPA_DOMAIN"
CRM_UAT_HOST="uat01.$IPA_DOMAIN"
CRM_PROD_HOST="prd01.$IPA_DOMAIN"
CRM_PROD2_HOST="prd02.$IPA_DOMAIN"

ERP_DEV_HOST="dev02.$IPA_DOMAIN"
ERP_UAT_HOST="uat02.$IPA_DOMAIN"
ERP_PROD_HOST="prd03.$IPA_DOMAIN"
ERP_PROD2_HOST="prd04.$IPA_DOMAIN"

# Hosts the CRM team should NOT have access to
RESTRICTED_PROD_HOST="prd03.$IPA_DOMAIN"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

# Check if SSH key exists
if [[ ! -f "$SSH_KEY" ]]; then
    echo "[!] SSH key not found at $SSH_KEY"
    echo "[ ] Creating Ed25519 key pair..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N ""
fi

echo "[ ] Using SSH key: $SSH_KEY.pub"
echo "$(cat "$SSH_KEY.pub")"
echo ""

# ==========================================
# Test 1: DEV environment (key-only)
# ==========================================
echo "=== TEST 1: DEV — Key-Only Authentication ==="
echo "[ ] CRM user -> CRM DEV host"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=publickey \
    -o BatchMode=yes \
    "$CRM_USER@$CRM_DEV_HOST" "echo '  ✅ SUCCESS: Authenticated with key only'" 2>&1 || \
    echo "  ❌ FAILED"

echo "[ ] Password auth (should fail on DEV):"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=password \
    -o PasswordAuthentication=yes \
    -o BatchMode=no \
    "$CRM_USER@$CRM_DEV_HOST" "echo success" 2>&1 | grep -q "Permission denied" && \
    echo "  ✅ CORRECT: Password authentication rejected" || \
    echo "  ❌ UNEXPECTED: Password authentication accepted"
echo ""

# ==========================================
# Test 2: UAT environment (key + password)
# ==========================================
echo "=== TEST 2: UAT — Key + Password Authentication ==="
echo "  ⚠️  Manual test required — run:"
echo "  ssh -i $SSH_KEY $CRM_USER@$CRM_UAT_HOST"
echo "  You will be prompted for password after key verification."
echo ""

# ==========================================
# Test 3: PROD environment (key + password + OTP)
# ==========================================
echo "=== TEST 3: PROD — Key + Password + OTP (MFA) ==="
echo "  ⚠️  Manual test required — run:"
echo "  ssh -i $SSH_KEY $CRM_USER@$CRM_PROD_HOST"
echo "  You will see two separate prompts:"
echo "    1. Password:  <enter password>"
echo "    2. OTP:       <enter 6-digit TOTP code>"
echo ""

# ==========================================
# Test 4: HBAC — Granular Per-Host Control
# ==========================================
echo "=== TEST 4: HBAC — Granular Per-Host Access ==="

echo "[ ] CRM user accessing CRM PROD host (should succeed):"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=publickey,keyboard-interactive \
    -o BatchMode=yes \
    "$CRM_USER@$CRM_PROD_HOST" "echo '  ✅ SUCCESS: CRM user accessed CRM PROD host'" 2>&1 || \
    echo "  ❌ FAILED"

echo "[ ] CRM user accessing RESTRICTED PROD host (should be denied by HBAC):"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=publickey \
    -o BatchMode=yes \
    "$CRM_USER@$RESTRICTED_PROD_HOST" "echo success" 2>&1 | grep -q "Permission denied" && \
    echo "  ✅ CORRECT: CRM user denied access to restricted host" || \
    echo "  ❌ UNEXPECTED: CRM user accessed restricted host (check HBAC rules)"
echo ""

# ==========================================
# Test 5: ERP User Access
# ==========================================
echo "=== TEST 5: ERP User — Environment Access ==="
echo "[ ] ERP user -> ERP DEV host (should succeed)"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=publickey \
    -o BatchMode=yes \
    "$ERP_USER@$ERP_DEV_HOST" "echo '  ✅ SUCCESS'" 2>&1 || \
    echo "  ❌ FAILED"

echo "[ ] ERP user -> CRM PROD host (should be denied by HBAC)"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=publickey \
    -o BatchMode=yes \
    "$ERP_USER@$CRM_PROD_HOST" "echo success" 2>&1 | grep -q "Permission denied" && \
    echo "  ✅ CORRECT: ERP user denied access to CRM host" || \
    echo "  ❌ UNEXPECTED: ERP user accessed CRM host (check HBAC rules)"
echo ""

# ==========================================
# Test 6: DevOps All-Access
# ==========================================
echo "=== TEST 6: DevOps — All-Environment Access ==="
echo "[ ] DevOps user -> any server (should succeed)"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=publickey \
    -o BatchMode=yes \
    "$DEVOPS_USER@$ERP_DEV_HOST" "echo '  ✅ SUCCESS: DevOps accessed ERP DEV'" 2>&1 || \
    echo "  ❌ FAILED"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=publickey \
    -o BatchMode=yes \
    "$DEVOPS_USER@$RESTRICTED_PROD_HOST" "echo '  ✅ SUCCESS: DevOps accessed restricted PROD'" 2>&1 || \
    echo "  ❌ FAILED"

echo ""
echo "=== Summary ==="
echo ""
echo "  DEV (CRM)  : $(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes -o PreferredAuthentications=publickey "$CRM_USER@$CRM_DEV_HOST" "echo OK" 2>/dev/null && echo '✅ PASS' || echo '❌ CHECK')"
echo "  DEV (ERP)  : $(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes -o PreferredAuthentications=publickey "$ERP_USER@$ERP_DEV_HOST" "echo OK" 2>/dev/null && echo '✅ PASS' || echo '❌ CHECK')"
echo "  HBAC deny  : $(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "$CRM_USER@$RESTRICTED_PROD_HOST" "echo OK" 2>/dev/null && echo '❌ CHECK RULES' || echo '✅ PASS')"
echo "  DEVOPS     : $(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes "$DEVOPS_USER@$RESTRICTED_PROD_HOST" "echo OK" 2>/dev/null && echo '✅ PASS' || echo '❌ CHECK')"
echo ""
echo "[+] Phase 9 complete."
echo "[+] Next: Phase 10 - Hardening and Troubleshooting"
