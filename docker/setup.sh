#!/bin/bash
# Local FreeIPA test environment setup
set -euo pipefail

IPA_SERVER="ipa.test.local"
IPA_DOMAIN="test.local"
IPA_REALM="TEST.LOCAL"
IPA_ADMIN_PASS="admin123"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== FreeIPA SSH MFA Docker Test Environment ==="
echo ""

# ------------------------------------------------------------------
echo "[1/7] Starting containers..."
docker compose -f "$BASE_DIR/docker-compose.yml" up -d
echo ""

# ------------------------------------------------------------------
echo "[2/7] Waiting for IPA server to be ready..."
for i in $(seq 1 60); do
    if docker exec ipa-server kinit admin <<< "$IPA_ADMIN_PASS" &>/dev/null; then
        echo "  IPA server is healthy (attempt $i)"
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "  ERROR: IPA server did not become ready in time"
        exit 1
    fi
    sleep 5
done
echo ""

enroll_client() {
    local name="$1"
    local ip="$2"
    local env_name="$3"

    echo "  Enrolling $name ($env_name)..."
    docker exec "$name" ipa-client-install \
        --domain="$IPA_DOMAIN" \
        --realm="$IPA_REALM" \
        --server="$IPA_SERVER" \
        --ip-address="$ip" \
        --enable-dns-updates \
        --mkhomedir \
        --force-join \
        --unattended \
        -p admin \
        -w "$IPA_ADMIN_PASS" \
        --no-ntp \
        &>/dev/null || true

    docker exec "$name" systemctl enable oddjobd --now &>/dev/null || true
    docker exec "$name" systemctl restart sssd sshd &>/dev/null || true

    # Add to host group
    docker exec ipa-server kinit admin <<< "$IPA_ADMIN_PASS" &>/dev/null
    docker exec ipa-server ipa hostgroup-add-member "${env_name}-servers" \
        --hosts="$name.$IPA_DOMAIN" &>/dev/null || true
}

echo "[3/7] Enrolling client containers..."
enroll_client "ipa-dev01" "172.20.0.11" "dev"
enroll_client "ipa-uat01" "172.20.0.12" "uat"
enroll_client "ipa-prd01" "172.20.0.13" "prod"
echo ""

# ------------------------------------------------------------------
echo "[4/7] Creating host groups and deployment groups..."
docker exec ipa-server kinit admin <<< "$IPA_ADMIN_PASS" &>/dev/null

for hg in dev-servers uat-servers prod-servers; do
    docker exec ipa-server ipa hostgroup-add "$hg" --desc="$(echo $hg | cut -d- -f1 | tr '[:lower:]' '[:upper:]') servers" &>/dev/null || true
done

for dg in crm-deployment erp-deployment monitoring devops; do
    docker exec ipa-server ipa group-add "$dg" --desc="$dg group" --nonposix &>/dev/null || true
done
echo ""

# ------------------------------------------------------------------
echo "[5/7] Creating test users..."
create_user() {
    local uid="$1"
    local first="$2"
    local last="$3"
    local groups="$4"

    docker exec ipa-server kinit admin <<< "$IPA_ADMIN_PASS" &>/dev/null
    docker exec ipa-server ipa user-add "$uid" \
        --first="$first" --last="$last" \
        --shell=/bin/bash \
        --password \
        --random &>/dev/null || true

    # Set a known password
    docker exec ipa-server bash -c "echo -e 'Passw0rd!\nPassw0rd!' | ipa passwd $uid" &>/dev/null || true

    # Add to groups
    IFS=',' read -ra grouplist <<< "$groups"
    for grp in "${grouplist[@]}"; do
        docker exec ipa-server ipa group-add-member "$grp" --users="$uid" &>/dev/null || true
    done
}

create_user "jackson" "Jackson" "Dev" "dev-servers,crm-deployment"
create_user "mbappe" "Mbappe" "Erp" "uat-servers,erp-deployment"
create_user "neymar" "Neymar" "Crm" "prod-servers,crm-deployment"
create_user "john" "John" "Crm" "dev-servers,uat-servers,prod-servers,crm-deployment"
create_user "doe" "Doe" "Ops" "dev-servers,uat-servers,prod-servers,devops"
echo ""

# ------------------------------------------------------------------
echo "[6/7] Configuring HBAC rules..."
docker exec ipa-server kinit admin <<< "$IPA_ADMIN_PASS" &>/dev/null

# Disable default allow_all
docker exec ipa-server ipa hbacrule-disable allow_all &>/dev/null || true

# Remove old env-based rules if present
for rule in dev-access uat-access prod-access; do
    docker exec ipa-server ipa hbacrule-del "$rule" &>/dev/null || true
done

# CRM deployment rules
docker exec ipa-server ipa hbacrule-add crm-dev-access --desc="CRM dev access" &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-user crm-dev-access --groups=crm-deployment &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-host crm-dev-access --hosts=dev01.test.local &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-service crm-dev-access --services=sshd &>/dev/null || true

docker exec ipa-server ipa hbacrule-add crm-uat-access --desc="CRM uat access" &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-user crm-uat-access --groups=crm-deployment &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-host crm-uat-access --hosts=uat01.test.local &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-service crm-uat-access --services=sshd &>/dev/null || true

docker exec ipa-server ipa hbacrule-add crm-prod-access --desc="CRM prod access" &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-user crm-prod-access --groups=crm-deployment &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-host crm-prod-access --hosts=prd01.test.local &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-service crm-prod-access --services=sshd &>/dev/null || true

# ERP deployment rules
docker exec ipa-server ipa hbacrule-add erp-all-access --desc="ERP all env access" &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-user erp-all-access --groups=erp-deployment &>/dev/null || true
for host in dev01.test.local uat01.test.local prd01.test.local; do
    docker exec ipa-server ipa hbacrule-add-host erp-all-access --hosts="$host" &>/dev/null || true
done
docker exec ipa-server ipa hbacrule-add-service erp-all-access --services=sshd &>/dev/null || true

# DevOps all-access rule (uses host groups for blanket access)
docker exec ipa-server ipa hbacrule-add devops-all-access --desc="DevOps all env SSH access" &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-user devops-all-access --groups=devops &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-host devops-all-access --hostgroups=dev-servers &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-host devops-all-access --hostgroups=uat-servers &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-host devops-all-access --hostgroups=prod-servers &>/dev/null || true
docker exec ipa-server ipa hbacrule-add-service devops-all-access --services=sshd &>/dev/null || true
echo ""

# ------------------------------------------------------------------
echo "[7/7] Generating test SSH key for admin user..."
SSH_KEY_FILE="/tmp/ipa_test_ed25519"
if [ ! -f "$SSH_KEY_FILE" ]; then
    ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -C "test@test.local" &>/dev/null
fi

PUB_KEY=$(cat "${SSH_KEY_FILE}.pub")
docker exec ipa-server ipa user-add admin --first=Admin --last=User &>/dev/null || true
docker exec ipa-server kinit admin <<< "$IPA_ADMIN_PASS" &>/dev/null
echo "$PUB_KEY" | docker exec -i ipa-server ipa user-add-certificate admin --certificate=- &>/dev/null || true
echo ""

# ------------------------------------------------------------------
echo "=== DONE ==="
echo ""
echo "Test users:"
echo "  jackson / Passw0rd!  (crm-deployment)"
echo "  mbappe  / Passw0rd!  (erp-deployment)"
echo "  neymar  / Passw0rd!  (crm-deployment, prod)"
echo "  john    / Passw0rd!  (crm-deployment, all envs)"
echo "  doe     / Passw0rd!  (devops, all envs)"
echo "  admin   / admin123  (IPA admin)"
echo ""
echo "Access matrix:"
echo "  DEV  (dev01):  key-only        - jackson, john, doe"
echo "  UAT  (uat01):  key + password  - mbappe, john, doe"
echo "  PROD (prd01):  key+pass+OTP    - neymar, john, doe"
echo ""
echo "Test SSH from host to dev01:"
echo "  ssh -i /tmp/ipa_test_ed25519 jackson@172.20.0.11"
echo ""
echo "Interactive login to a client:"
echo "  docker exec -it ipa-dev01 bash"
echo ""
echo "To stop:  docker compose -f docker/docker-compose.yml down"
echo "To wipe:  docker compose -f docker/docker-compose.yml down -v"
