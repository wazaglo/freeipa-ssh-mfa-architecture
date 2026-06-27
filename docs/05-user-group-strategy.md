# Phase 5: User and Group Creation Strategy

## Naming Conventions

| Resource | Convention | Example |
|---|---|---|
| Users | Lowercase first name | `jackson`, `neymar`, `john` |
| Deployment Groups | `{project}-deployment` | `crm-deployment`, `erp-deployment` |
| Special Groups | `devops` | Cross-environment admin access |
| Host Groups | `{env}-servers` | `dev-servers`, `uat-servers`, `prod-servers` |
| OTP Tokens | `{username}-prod-otp` | `neymar-prod-otp` |

## Group Strategy

**Host groups** (`dev-servers`, `uat-servers`, `prod-servers`) are used ONLY by Ansible to discover which environment a server belongs to and apply the correct `sshd_config`. They are NOT used for authorization.

**Deployment groups** are FreeIPA user groups that control authorization via HBAC rules. Users are added to one or more deployment groups, and each deployment group has HBAC rules that grant access to specific individual hosts.

```
┌─────────────────────────────────────────────────────────────┐
│                Deployment Groups (AUTHORIZATION)            │
│                                                             │
│  crm-deployment    erp-deployment    monitoring    devops  │
│  ──────────────    ──────────────    ──────────    ──────  │
│  ┌─ neymar         ┌─ mbappe         ┌─ doe        ┌─ doe  │
│  └─ john           └─ jackson        └─ neymar     └─ admin│
│                                                             │
│  Each group maps to specific hosts via HBAC rules:          │
│  crm-deployment → dev01, uat01, prd01, prd02               │
│  erp-deployment → dev02, uat02, prd03, prd04               │
│  monitoring     → all prod servers                          │
│  devops         → ALL servers                               │
└─────────────────────────────────────────────────────────────┘
```

## Create Host Groups (Ansible Use Only)

```bash
kinit admin

ipa hostgroup-add dev-servers --desc="DEV environment servers"
ipa hostgroup-add uat-servers --desc="UAT environment servers"
ipa hostgroup-add prod-servers --desc="PRODUCTION environment servers"

# Add hosts after enrollment — Ansible uses host groups to apply sshd_config
ipa hostgroup-add-member dev-servers --hosts=dev01.devuatprod.com
ipa hostgroup-add-member uat-servers --hosts=uat01.devuatprod.com
ipa hostgroup-add-member prod-servers --hosts=prd01.devuatprod.com
```

## Create Deployment Groups

```bash
ipa group-add crm-deployment --desc="CRM project team" --nonposix
ipa group-add erp-deployment --desc="ERP project team" --nonposix
ipa group-add monitoring --desc="Monitoring team" --nonposix
ipa group-add devops --desc="DevOps engineers (all environments)" --nonposix
```

## Create Users

```bash
# These are assigned to deployment groups, NOT env groups

ipa user-add jackson \
    --first=Jackson --last=Dev \
    --email=jackson@devuatprod.com \
    --title="Developer" \
    --shell=/bin/bash \
    --homedir=/home/jackson \
    --noprivate
ipa group-add-member erp-deployment --users=jackson

ipa user-add mbappe \
    --first=Kylian --last=Mbappe \
    --email=mbappe@devuatprod.com \
    --title="QA Engineer" \
    --shell=/bin/bash \
    --homedir=/home/mbappe \
    --noprivate
ipa group-add-member erp-deployment --users=mbappe

ipa user-add neymar \
    --first=Neymar --last=Jr \
    --email=neymar@devuatprod.com \
    --title="Production Engineer" \
    --shell=/bin/bash \
    --homedir=/home/neymar \
    --noprivate
ipa group-add-member crm-deployment --users=neymar
ipa group-add-member monitoring --users=neymar

ipa user-add john \
    --first=John --last=Doe \
    --email=john@devuatprod.com \
    --title="Senior Engineer" \
    --shell=/bin/bash \
    --homedir=/home/john \
    --noprivate
ipa group-add-member crm-deployment --users=john

ipa user-add doe \
    --first=Jane --last=Doe \
    --email=doe@devuatprod.com \
    --title="DevOps Engineer" \
    --shell=/bin/bash \
    --homedir=/home/doe \
    --noprivate
ipa group-add-member devops --users=doe
ipa group-add-member monitoring --users=doe
```

## ⚠️ Important: Login Shell

FreeIPA's default login shell is `/bin/sh`. Always specify `--shell=/bin/bash` when creating users:

```bash
ipa user-add <user> --shell=/bin/bash ...
```

If a user was already created without this flag, update it on the IPA server:

```bash
ipa user-mod <user> --shell=/bin/bash
```

Then on each client server, invalidate the cached value:

```bash
sss_cache -u <user>
```

Without this invalidation, the client continues serving the old shell even after `systemctl restart sssd`. The package `sssd-tools` provides `sss_cache`.

## User Attribute Reference

| Attribute | Purpose | Example |
|---|---|---|
| `--shell` | Login shell (defaults to `/bin/sh`!) | `/bin/bash` |
| `--homedir` | Home directory path | `/home/neymar` |
| `--noprivate` | Skip private group creation | (uses default group) |
| `--sshpubkey` | SSH public key | `ssh-ed25519 AAAA...` |
| `--user-auth-type` | Authentication type | `password`, `otp`, `pkinit` |

## How Access Works

**The target server determines auth method, not the user's group.**  
**Authorization is granted via deployment group → specific host HBAC rules.**

```
User: john (Senior Engineer)
  Deployment group: crm-deployment

  HBAC rule: crm-prod-access
    Who:   crm-deployment
    What:  prd01.devuatprod.com, prd02.devuatprod.com  (specific hosts)
    Which: sshd

  john → prd01 → auth: key + password + OTP (enforced by server via prod-servers host group)
  john → prd02 → auth: key + password + OTP (enforced by server via prod-servers host group)
  john → prd03 → DENIED (no HBAC rule grants access — prd03 is not in the rule)
```

## Adding a New Server to an Existing Deployment

```bash
# 1. Enroll server and add to host group (for Ansible sshd_config)
ipa hostgroup-add-member prod-servers --hosts=prd06.devuatprod.com

# 2. Add the specific host to the deployment's HBAC rule
ipa hbacrule-add-host crm-prod-access --hosts=prd06.devuatprod.com
```

## Verification

```bash
# List all users
ipa user-find

# Show user details
ipa user-show neymar --all

# List group memberships
ipa user-show neymar --all | grep -i member

# Show host groups (Ansible use only)
ipa hostgroup-find

# Show deployment groups
ipa group-find

# Show HBAC rules
ipa hbacrule-find
```

## Next Steps

Proceed to [Phase 6: SSH Integration and Key Management](06-ssh-key-management.md).
