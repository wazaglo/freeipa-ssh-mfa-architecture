# Phase 1: Architecture Design & Prerequisites

## Overview

Centralized authentication system using FreeIPA to manage SSH access across DEV, UAT, and PRODUCTION environments.

## Core Model: Server-Group-Enforced Authentication

**Auth method is determined by the target server's host group, not by the user.**

```
                 ┌─────────────────────────────────────────────┐
                 │            FreeIPA Server                   │
                 │                                             │
                 │  ┌─ KDC (Kerberos) ──────► Password + OTP  │
                 │  ├─ LDAP ────────────────► Users / Groups  │
                 │  ├─ DNS ─────────────────► devuatprod.com  │
                 │  ├─ HBAC ────────────────► AuthZ Policy   │
                 │  └─ SSH Keys ────────────► Key Mgmt       │
                 └──────────────────┬──────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐
│  dev-servers       │   │  uat-servers       │   │  prod-servers      │
│  Host Group        │   │  Host Group        │   │  Host Group        │
│                    │   │                    │   │                    │
│  Authentication:   │   │  Authentication:   │   │  Authentication:   │
│  publickey         │   │  publickey,passwd  │   │  publickey,kbd-int │
│  (key only)        │   │  (key + password)  │   │  (key+pass+OTP)    │
│                    │   │                    │   │                    │
│  dev01...devXX     │   │  uat01...uatXX     │   │  prd01...prdXX     │
└───────────────────┘   └───────────────────┘   └───────────────────┘
```

## How It Works

### 1. Authentication — Server Enforces the Method

Each server's `sshd_config` enforces an `AuthenticationMethods` directive based on its host group:

| Host Group | `sshd_config` | Auth Flow |
|---|---|---|
| `dev-servers` | `AuthenticationMethods publickey` | Key only — no password prompt |
| `uat-servers` | `AuthenticationMethods publickey,password` | Key, then password |
| `prod-servers` | `AuthenticationMethods publickey,keyboard-interactive` | Key, then Password:, then OTP: |

The server decides **how** you authenticate — the user just provides the credentials.

### 2. Authorization — HBAC Controls Who Can Go Where

Once authenticated, HBAC rules in FreeIPA decide if you're **authorized** to access that server.

**Host groups (`dev-servers`, `uat-servers`, `prod-servers`) are used ONLY by Ansible to apply the correct `sshd_config`.** They are NOT used in HBAC rules. Authorization is done separately using **deployment groups** mapped to **specific individual hosts**.

```
HBAC Rules (deployment groups → specific hosts):
  crm-dev-access:    crm-deployment  →  dev01.devuatprod.com                       →  sshd
  crm-uat-access:    crm-deployment  →  uat01.devuatprod.com                       →  sshd
  crm-prod-access:   crm-deployment  →  prd01.devuatprod.com, prd02.devuatprod.com  →  sshd
  erp-all-access:    erp-deployment  →  dev02, uat02, prd03, prd04                  →  sshd
  monitoring-access: monitoring      →  prd01, prd02, prd03, prd04, prd05           →  sshd
  devops-access:     devops          →  ALL servers                                 →  sshd
```

This means being in a host group's environment does **not** grant blanket access to all servers in that group. Each user gets access only to the specific hosts their deployment group is mapped to.

For example:
- **neymar** in `crm-deployment` → can access only dev01, uat01, prd01, prd02
- **mbappe** in `erp-deployment` → can access only dev02, uat02, prd03, prd04
- **doe** in `monitoring` → can access all prod servers but not dev/uat servers

### 3. Identity — Users, Keys, Groups in FreeIPA

All users, SSH keys, and groups exist only in FreeIPA — never in `/etc/passwd` on clients. SSSD on each client resolves identities from FreeIPA LDAP.

## Enrollment Workflow

```
1. Provision server
        │
        ▼
2. Enroll into FreeIPA (ipa-client-install)
        │
        ▼
3. Add server to host group in FreeIPA (Ansible uses this for sshd_config):
   ipa hostgroup-add-member prod-servers --hosts=prd01.devuatprod.com
        │
        ▼
4. Run Ansible:
   → Detects host group membership from IPA
   → Applies correct sshd_config
   → Configures SSSD, PAM
        │
        ▼
5. Admin creates or updates HBAC rule:
   ipa hbacrule-add-host crm-prod-access --hosts=prd01.devuatprod.com
        │
        ▼
6. Grant user access (add to deployment group):
   ipa group-add-member crm-deployment --users=neymar
        │
        ▼
7. Done — neymar SSHs to prd01 and gets key+password+OTP
```

## Three-Layer Separation

```
┌─────────────────────────────────────────────────────┐
│                  FreeIPA Server                      │
│                                                      │
│  ┌─────────────────────────────────────────────┐   │
│  │  Layer 1: Identity                           │   │
│  │  • Users (mbappe, neymar, john, etc.)        │   │
│  │  • SSH public keys                           │   │
│  │  • Kerberos principals                       │   │
│  │  • Deployment groups (crm-deployment, etc.)  │   │
│  │  • Host groups (prod-servers, dev-servers)   │   │
│  │    └─ Ansible use ONLY (never HBAC)         │   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│  ┌─────────────────────────────────────────────┐   │
│  │  Layer 2: Authorization (HBAC)               │   │
│  │  • crm-prod-access:  crm-deployment → prd01 │   │
│  │  • erp-all-access:   erp-deployment → dev02 │   │
│  │  • devops-access:    devops → ALL hosts     │   │
│  │  └─ Deployment groups → specific hosts      │   │
│  └─────────────────────────────────────────────┘   │
│                                                      │
│  ┌─────────────────────────────────────────────┐   │
│  │  Layer 3: OTP Tokens                         │   │
│  │  • TOTP tokens for prod users                │   │
│  │  • Per-user auth types                       │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
         │
         │  SSSD (on each client)
         ▼
┌─────────────────────────────────────────────────────┐
│  Server-Level Enforcement                           │
│                                                     │
│  • sshd_config.AuthenticationMethods                 │
│  • PAM stacks (pam_sss.so)                          │
│  • sssd.conf (pam_verbosity)                        │
└─────────────────────────────────────────────────────┘
```

## Infrastructure Requirements

| Component | Specification |
|---|---|
| IPA Server OS | CentOS Stream 9 |
| Client OS | Debian, RHEL, or CentOS |
| FreeIPA | 4.13+ |
| Domain | `devuatprod.com` (replace for your deployment) |
| Kerberos Realm | `DEVUATPROD.COM` |
| DNS | IPA-managed (integrated DNS server) |
| NTP | chronyd (all servers synchronized) |

## Port Requirements

| Port | Protocol | Service | Direction |
|---|---|---|---|
| 53 | TCP/UDP | DNS | All servers ↔ IPA |
| 88 | TCP/UDP | Kerberos | All servers ↔ IPA |
| 389 | TCP | LDAP | Clients → IPA |
| 443 | TCP | HTTPS (IPA Web UI) | Clients → IPA |
| 464 | TCP/UDP | kpasswd | Clients → IPA |
| 749 | TCP | kadmin | IPA server only |

## Environment-Specific Authentication Matrix

| Factor | DEV | UAT | PROD |
|---|---|---|---|
| SSH Public Key | ✅ Required | ✅ Required | ✅ Required |
| Password | ❌ Not allowed | ✅ Required | ✅ Required |
| OTP (TOTP) | ❌ Not allowed | ❌ Not allowed | ✅ Required |
| `AuthenticationMethods` | `publickey` | `publickey,password` | `publickey,keyboard-interactive` |
| PAM OTP Prompts | 0 | 0 | 2 (separate) |

## Next Steps

Proceed to [Phase 2: FreeIPA Server Installation](02-server-installation.md).
