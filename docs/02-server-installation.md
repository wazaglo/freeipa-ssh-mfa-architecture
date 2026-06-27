# Phase 2: FreeIPA Server Installation

## Prerequisites

```
OS: CentOS Stream 9
Hostname: ipa.devuatprod.com
IP: 10.0.0.47 (static)
RAM: 4GB minimum (8GB recommended for 30+ clients)
Disk: 20GB minimum
DNS forwarder: <YOUR_DNS_FORWARDER>
```

## Step 1: System Preparation

```bash
# Set hostname
hostnamectl set-hostname ipa.devuatprod.com

# Update system
dnf update -y

# Install chrony and sync time
dnf install -y chrony
systemctl enable --now chronyd
chronyc sources -v

# Configure firewalld
systemctl enable --now firewalld
firewall-cmd --add-service=freeipa-ldap --add-service=freeipa-ldaps \
    --add-service=dns --add-service=ntp --add-service=kerberos \
    --add-service=ssh --add-service=http --add-service=https --permanent
firewall-cmd --reload
```

## Step 2: Install FreeIPA Server Packages

```bash
# Enable the IDM module (CentOS Stream 9)
dnf module enable -y idm:DL1

# Install FreeIPA with DNS
dnf install -y @idm:DL1 ipa-server ipa-server-dns
```

## Step 3: Run IPA Server Installer

```bash
ipa-server-install \
    --setup-dns \
    --auto-forwarders \
    --auto-reverse \
    --ds-password="YourDMPasswordHere" \
    --admin-password="YourAdminPasswordHere" \
    --domain=devuatprod.com \
    --realm=DEVUATPROD.COM \
    --hostname=ipa.devuatprod.com \
    --ip-address=10.0.0.47 \
    --mkhomedir \
    --unattended
```

### Key Installer Options

| Option | Purpose |
|---|---|
| `--setup-dns` | Configures integrated DNS server |
| `--auto-forwarders` | Automatically detects and sets DNS forwarders |
| `--auto-reverse` | Creates reverse DNS zones automatically |
| `--mkhomedir` | Creates home directories on first login (via oddjobd) |
| `--unattended` | Non-interactive mode |

## Step 4: Post-Installation Verification

```bash
# Authenticate as admin
kinit admin

# Test basic IPA operations
ipa user-find admin
ipa host-find

# Verify DNS
dig +short SOA devuatprod.com
dig +short SRV _kerberos._tcp.devuatprod.com
dig +short SRV _ldap._tcp.devuatprod.com
dig +short -x 10.0.0.47

# Check IPA services status
ipa service-find
```

## Step 5: Save Credentials

```bash
# Store passwords in a secure location
echo "YourAdminPassword" > /root/.ipa_admin_pass
echo "YourDMPassword" > /root/.ipa_dm_pass
chmod 600 /root/.ipa_admin_pass /root/.ipa_dm_pass
```

## Troubleshooting

| Issue | Resolution |
|---|---|
| Time sync failure | Check `chronyc tracking`, ensure NTP ports open (123/UDP) |
| DNS resolution failure | Check `/etc/resolv.conf`, ensure IPA is authoritative |
| Port conflicts | Verify no existing DNS/DHCP services running |
| SELinux denials | Check `ausearch -m avc`, install missing SELinux booleans |
| Module enable fails | `dnf clean all && dnf module reset idm && dnf module enable idm:DL1` |

## DNSSEC Note

If your DNS forwarder does not support DNSSEC (e.g., internal corporate DNS), disable it in IPA:

```bash
ipa dnsconfig-mod --disable-dnssec
```

## Next Steps

Proceed to [Phase 3: Domain, DNS, and Kerberos Configuration](03-domain-dns-kerberos.md).
