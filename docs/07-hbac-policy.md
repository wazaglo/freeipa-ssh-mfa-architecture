# Phase 7: HBAC Policy — Authorization Layer

## Overview

Host-Based Access Control (HBAC) rules define **who can access which servers** via SSH. This is the authorization layer — separate from authentication (which is enforced by each server's `sshd_config`).

## How HBAC Fits the Architecture

```
Layer 1: Identity      FreeIPA users, deployment groups, host groups
                           │
Layer 2: AuthZ (HBAC)  Deployment groups → specific individual hosts → sshd
                           │
Layer 3: AuthN (SSHD)  Server-enforced sshd_config (key / pass / OTP)
```

A user must pass **both** layers:
1. **Authentication** — provide valid credentials (server enforces the method via its host group's sshd_config)
2. **Authorization** — HBAC allows access to that specific host (via deployment group rule)

## Key Principle

**Host groups are NOT used in HBAC rules.** Host groups (`dev-servers`, `uat-servers`, `prod-servers`) exist only for Ansible to discover servers and apply the correct `sshd_config`. Authorization is done via **deployment groups** mapped to **specific individual hosts**.

## Deployment Group-to-Host Mapping

A user gets access by being a member of a deployment group. Each deployment group has HBAC rules that list specific hosts:

```
Deployment Group         Hosts Accessible
─────────────────        ─────────────────────────────────
crm-deployment           dev01, uat01, prd01, prd02
erp-deployment           dev02, uat02, prd03, prd04
monitoring               prd01, prd02, prd03, prd04, prd05
devops                   ALL servers (dev01, dev02, uat01, uat02, prd01-prd05)
```

## HBAC Rule Design

```
┌─────────────────────────────────────────────────────────────┐
│                    HBAC Rules                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  crm-dev-access:                                            │
│    Who:   crm-deployment                                    │
│    What:  dev01.devuatprod.com                              │
│    Which: sshd                                              │
│                                                             │
│  crm-uat-access:                                            │
│    Who:   crm-deployment                                    │
│    What:  uat01.devuatprod.com                              │
│    Which: sshd                                              │
│                                                             │
│  crm-prod-access:                                           │
│    Who:   crm-deployment                                    │
│    What:  prd01.devuatprod.com, prd02.devuatprod.com        │
│    Which: sshd                                              │
│                                                             │
│  erp-all-access:                                            │
│    Who:   erp-deployment                                    │
│    What:  dev02.devuatprod.com, uat02.devuatprod.com,       │
│           prd03.devuatprod.com, prd04.devuatprod.com        │
│    Which: sshd                                              │
│                                                             │
│  monitoring-access:                                         │
│    Who:   monitoring                                         │
│    What:  prd01..prd05.devuatprod.com                       │
│    Which: sshd                                              │
│                                                             │
│  devops-all-access:                                         │
│    Who:   devops                                            │
│    What:  ALL servers                                       │
│    Which: sshd                                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Implementation

```bash
kinit admin

# 1. Disable default allow-all rule (critical security step)
ipa hbacrule-disable allow_all

# 2. Create deployment-specific HBAC rules with individual hosts

# CRM: dev
ipa hbacrule-add crm-dev-access --desc="CRM team access DEV server"
ipa hbacrule-add-user crm-dev-access --groups=crm-deployment
ipa hbacrule-add-host crm-dev-access --hosts=dev01.devuatprod.com
ipa hbacrule-add-service crm-dev-access --services=sshd

# CRM: uat
ipa hbacrule-add crm-uat-access --desc="CRM team access UAT server"
ipa hbacrule-add-user crm-uat-access --groups=crm-deployment
ipa hbacrule-add-host crm-uat-access --hosts=uat01.devuatprod.com
ipa hbacrule-add-service crm-uat-access --services=sshd

# CRM: prod (two specific hosts)
ipa hbacrule-add crm-prod-access --desc="CRM team access PROD servers"
ipa hbacrule-add-user crm-prod-access --groups=crm-deployment
ipa hbacrule-add-host crm-prod-access --hosts=prd01.devuatprod.com
ipa hbacrule-add-host crm-prod-access --hosts=prd02.devuatprod.com
ipa hbacrule-add-service crm-prod-access --services=sshd

# ERP: all environments
ipa hbacrule-add erp-all-access --desc="ERP team access all environments"
ipa hbacrule-add-user erp-all-access --groups=erp-deployment
ipa hbacrule-add-host erp-all-access --hosts=dev02.devuatprod.com
ipa hbacrule-add-host erp-all-access --hosts=uat02.devuatprod.com
ipa hbacrule-add-host erp-all-access --hosts=prd03.devuatprod.com
ipa hbacrule-add-host erp-all-access --hosts=prd04.devuatprod.com
ipa hbacrule-add-service erp-all-access --services=sshd

# Monitoring: prod only
ipa hbacrule-add monitoring-access --desc="Monitoring team access PROD servers"
ipa hbacrule-add-user monitoring-access --groups=monitoring
ipa hbacrule-add-host monitoring-access --hosts=prd01.devuatprod.com
ipa hbacrule-add-host monitoring-access --hosts=prd02.devuatprod.com
ipa hbacrule-add-host monitoring-access --hosts=prd03.devuatprod.com
ipa hbacrule-add-host monitoring-access --hosts=prd04.devuatprod.com
ipa hbacrule-add-host monitoring-access --hosts=prd05.devuatprod.com
ipa hbacrule-add-service monitoring-access --services=sshd

# 3. DevOps all-access rule (uses host groups for blanket access — this is the exception)
ipa hbacrule-add devops-all-access --desc="DevOps engineers access all environments"
ipa hbacrule-add-user devops-all-access --groups=devops
ipa hbacrule-add-host devops-all-access --hostgroups=dev-servers
ipa hbacrule-add-host devops-all-access --hostgroups=uat-servers
ipa hbacrule-add-host devops-all-access --hostgroups=prod-servers
ipa hbacrule-add-service devops-all-access --services=sshd
```

## Adding Users to Deployment Groups

```bash
# Add neymar to CRM deployment
ipa group-add-member crm-deployment --users=neymar

# Add mbappe to ERP deployment
ipa group-add-member erp-deployment --users=mbappe
```

No need to change sshd_config, host groups, or enrollment — the auth method on each server stays the same.

## Adding a New Server to an Existing Deployment

When a new server is provisioned:

```bash
# 1. Enroll it and add to host group (Ansible will apply sshd_config)
ipa hostgroup-add-member prod-servers --hosts=prd06.devuatprod.com

# 2. Add it to the relevant deployment's HBAC rule
ipa hbacrule-add-host crm-prod-access --hosts=prd06.devuatprod.com
```

Users in `crm-deployment` now automatically get access to `prd06` — no user changes needed.

## Testing Rules

```bash
# Can neymar (crm-deployment) access prd01?
ipa hbac-test --user=neymar --host=prd01.devuatprod.com --service=sshd
# → ALLOWED (neymar is in crm-deployment, prd01 is in crm-prod-access rule)

# Can neymar access prd03?
ipa hbac-test --user=neymar --host=prd03.devuatprod.com --service=sshd
# → DENIED (neymar is not in a deployment group that has access to prd03)

# Can mbappe (erp-deployment) access dev02?
ipa hbac-test --user=mbappe --host=dev02.devuatprod.com --service=sshd
# → ALLOWED (mbappe is in erp-deployment, dev02 is in erp-all-access rule)

# Can jackson (erp-deployment) access dev01?
ipa hbac-test --user=jackson --host=dev01.devuatprod.com --service=sshd
# → DENIED (erp-deployment only has dev02, not dev01)
```

## HBAC Evaluation Order

1. If a DENY rule matches → access is denied immediately
2. If an ALLOW rule matches → access is allowed
3. If no rule matches → access is denied (when `allow_all` is disabled)

## Why Per-Host HBAC Instead of Host Groups?

| Approach | Granularity | Management |
|---|---|---|
| User groups → host groups (old) | All servers in host group | Low effort, broad access |
| Deployment groups → specific hosts (new) | Per-server | Moderate effort, precise access |

The per-host model ensures that adding a server to a host group (for Ansible config purposes) does NOT automatically grant anyone access to it. Access must be explicitly granted by adding the host to the appropriate HBAC rule.

## Next Steps

Proceed to [Phase 8: MFA (OTP) for Production](08-otp-mfa.md).
