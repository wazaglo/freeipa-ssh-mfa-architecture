# FreeIPA SSH MFA Architecture

Centralized authentication system using FreeIPA to manage SSH access across DEV (key-only), UAT (key+password), and PRODUCTION (key+password+OTP) environments.

> **Security:** This repository contains hardcoded credentials and real infrastructure values from a test deployment. Review [SECURITY.md](SECURITY.md) and complete the pre-deployment checklist before any production use.

**Domain:** `devuatprod.com` · **Realm:** `DEVUATPROD.COM`  
**IPA Server:** `ipa.devuatprod.com` (10.0.0.47)  

> **Important:** All domain names, IP addresses, hostnames, and user names in this repository are real values from a test environment. Replace every occurrence with your own infrastructure values before deploying.

## Core Model

**Auth method is determined by the target server's host group, not by the user.**  
**Authorization is determined by deployment group membership mapped to specific hosts.**

```
Host Groups (Ansible only — apply correct sshd_config):
  dev-servers    →  publickey (key only)
  uat-servers    →  publickey,password (key + pass)
  prod-servers   →  publickey,keyboard-interactive (key+pass+OTP)

Authorization (HBAC — deployment groups → specific hosts):
  crm-deployment →  dev01, uat01, prd01, prd02  (per-host explicit)
  erp-deployment →  dev02, uat02, prd03, prd04  (per-host explicit)
  devops         →  ALL servers                  (override)
```

- **Authentication** is enforced by each server's `sshd_config` based on its FreeIPA host group
- **Authorization** is controlled by HBAC rules: deployment groups → specific individual hosts
- **Identity** is managed entirely in FreeIPA (users, keys, groups)

## Workflow

```
1. Enroll server → 2. Assign to host group → 3. Ansible applies config → 4. Admin creates HBAC rule with specific hosts → 5. Admin adds user to deployment group → 6. Done
```

## Project Structure

```
├── docs/              # Phase-by-phase implementation guides (1-10)
├── scripts/           # Copy-paste shell scripts (one per phase)
├── ansible/           # Automation playbooks and roles
│   ├── inventory/     # Per-environment inventory files
│   ├── playbooks/     # Playbooks for automation
│   └── roles/         # Reusable Ansible roles
├── docker/            # Local testing environment (Docker Compose)
│   ├── configs/       # Per-environment sshd_config
│   ├── sssd/          # Per-environment sssd.conf
│   ├── setup.sh       # Automated environment bootstrap
│   └── README.md      # Comprehensive testing guide
└── configs/           # Template configuration files
    ├── sssd/          # SSSD configs per environment
    ├── ssh/           # sshd_config templates
    ├── pam/           # PAM stack for PROD MFA
    ├── ipa/           # HBAC rules LDIF
    └── krb5/          # KDC OTP plugin config
```

## Local Testing with Docker

A self-contained Docker Compose environment for testing the full FreeIPA MFA stack locally:

```bash
docker compose -f docker/docker-compose.yml up -d
./docker/setup.sh
```

This starts an IPA server + 3 clients (DEV/UAT/PROD), enrolls them, creates test users, and configures HBAC rules. See [docker/README.md](docker/README.md) for details.

## Quick Start

> **Prerequisite:** Set environment variables before running scripts:
> ```bash
> export IPA_ADMIN_PASSWORD="your-secure-admin-password"
> export IPA_DM_PASSWORD="your-secure-dm-password"
> ```
> See [SECURITY.md](SECURITY.md) for the full pre-deployment checklist.

```bash
# 1. Install FreeIPA server (Phase 2)
./scripts/phase-2-install-ipa-server.sh

# 2. Enroll a client (Phase 4)
./scripts/phase-4-enroll-client.sh prod

# 3. Create users and deployment groups (Phase 5)
./scripts/phase-5-create-users.sh

# 4. Upload SSH keys (Phase 6)
./scripts/phase-6-ssh-key-setup.sh

# 5. Configure HBAC rules — deployment groups → specific hosts (Phase 7)
./scripts/phase-7-hbac-rules.sh

# 6. Configure OTP for production (Phase 8)
./scripts/phase-8-otp-mfa.sh
```

## Or Deploy with Ansible

> **Note:** These playbooks read passwords from plaintext files. For production, use [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html).

```bash
# Install IPA server
ansible-playbook -i ansible/inventory/prod.yml ansible/playbooks/install-ipa-server.yml

# Enroll all clients (Ansible detects host group and applies correct SSH config)
ansible-playbook -i ansible/inventory/prod.yml ansible/playbooks/enroll-clients.yml

# Configure HBAC
ansible-playbook -i ansible/inventory/prod.yml ansible/playbooks/configure-hbac.yml
```

## Ansible Prerequisites

The playbooks assume SSH access to target hosts already exists. Before running any playbook, you must configure initial SSH connectivity.

### Option A: Pre-distribute SSH key (any environment)

Add an `ansible` user with sudo and your public key to every target host:

```bash
# On each target host (or via cloud-init):
useradd -m -G wheel ansible
mkdir -p /home/ansible/.ssh
echo "<your-public-key>" > /home/ansible/.ssh/authorized_keys
chmod 700 /home/ansible/.ssh && chmod 600 /home/ansible/.ssh/authorized_keys
echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
```

Then set the user in the inventory:

```yaml
# ansible/inventory/prod.yml
all:
  vars:
    ansible_user: ansible
    ansible_become: yes
    ansible_become_method: sudo
```

### Option B: Run from an IPA-enrolled host

If your Ansible control node is already enrolled in FreeIPA, use Kerberos so no pre-distributed SSH key is needed:

```bash
kinit admin
ansible-playbook -i ansible/inventory/prod.yml ansible/playbooks/enroll-clients.yml
```

> **Note:** The `configure-hbac.yml` playbook runs on `hosts: ipa_servers` and executes locally — it does not need remote SSH access at all.

## CI / Linting

The repository includes GitHub Actions CI that runs on every push and pull request to `main`:

- **ShellCheck** — Lints all bash scripts for syntax errors and common mistakes. Uses inline `--exclude` flags for intentional patterns, reports warnings and above.
- **Yamllint** — Validates all YAML files (Ansible playbooks, inventory, configs) for syntax and formatting. Configured via `.yamllint` with Ansible-compatible rules (200-char line limit, `yes`/`no` truthy values, 2-space indentation).

## Documentation

| Phase | Title | Script |
|---|---|---|
| 1 | [Architecture & Prerequisites](docs/01-architecture-design.md) | `phase-1-prerequisites.sh` |
| 2 | [Server Installation](docs/02-server-installation.md) | `phase-2-install-ipa-server.sh` |
| 3 | [Domain, DNS & Kerberos](docs/03-domain-dns-kerberos.md) | `phase-3-domain-config.sh` |
| 4 | [Client Enrollment](docs/04-client-enrollment.md) | `phase-4-enroll-client.sh` |
| 5 | [User & Group Strategy](docs/05-user-group-strategy.md) | `phase-5-create-users.sh` |
| 6 | [SSH Key Management](docs/06-ssh-key-management.md) | `phase-6-ssh-key-setup.sh` |
| 7 | [HBAC Policy](docs/07-hbac-policy.md) | `phase-7-hbac-rules.sh` |
| 8 | [MFA (OTP) for Production](docs/08-otp-mfa.md) | `phase-8-otp-mfa.sh` |
| 9 | [Testing Auth Flows](docs/09-testing-auth-flows.md) | `phase-9-test-auth.sh` |
| 10 | [Hardening & Troubleshooting](docs/10-hardening-troubleshooting.md) | `phase-10-hardening.sh` |
