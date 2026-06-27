# Phase 3: Domain Setup, DNS, and Kerberos Realm Configuration

## Overview

FreeIPA server installation handles domain, DNS, and Kerberos automatically. This phase verifies correct configuration and performs any manual adjustments needed.

## 1. Verify DNS Configuration

```bash
# Authenticate
kinit admin

# List DNS zones
ipa dnszone-find

# Check forward zone
dig +short SOA devuatprod.com
dig +short NS devuatprod.com

# Check SRV records (critical for Kerberos and LDAP discovery)
dig +short SRV _kerberos._tcp.devuatprod.com
dig +short SRV _kerberos._udp.devuatprod.com
dig +short SRV _ldap._tcp.devuatprod.com
dig +short SRV _kpasswd._tcp.devuatprod.com
dig +short SRV _ntp._udp.devuatprod.com

# Test reverse DNS
dig +short -x 10.0.0.47
```

### Expected SRV Records

| Service | Target |
|---|---|
| `_kerberos._tcp` | `ipa.devuatprod.com` |
| `_kerberos._udp` | `ipa.devuatprod.com` |
| `_ldap._tcp` | `ipa.devuatprod.com` |
| `_kpasswd._tcp` | `ipa.devuatprod.com` |

## 2. Verify Kerberos Configuration

```bash
# Check Kerberos ticket
klist

# Get a ticket-granting ticket
kinit admin

# Check ticket details
klist -e

# Verify service principal
kvno host/ipa.devuatprod.com

# Test Kerberized LDAP query
ldapsearch -Y GSSAPI -H ldap://ipa.devuatprod.com -b "dc=devuatprod,dc=com" cn=admin
```

## 3. Configure DNS Reverse Zone (if not auto-created)

```bash
# Check if reverse zone exists
ipa dnszone-find | grep -A5 "in-addr.arpa"

# If missing, create it
ipa dnszone-add 10.0.0.0/24

# Add PTR record for IPA server
ipa dnsrecord-add 10.0.0.0/24 47 --ptr-hostname=ipa.devuatprod.com.
```

## 4. DNS Forwarders Configuration

```bash
# List current forwarders
ipa dnsforwardzone-find

# Set forwarders (if not auto-detected)
ipa dnsconfig-mod --forwarder=<YOUR_DNS_FORWARDER>
```

## 5. Client DNS Configuration

Clients must be able to resolve `*.devuatprod.com` via the IPA server's integrated DNS.

### Option A: IPA as Primary DNS (Recommended)

IPA resolves `devuatprod.com` authoritatively and forwards unknown queries to your existing corporate DNS.

```
# /etc/resolv.conf
search devuatprod.com
nameserver 10.0.0.47      # IPA (primary)
nameserver <YOUR_EXISTING_DNS>  # corporate DNS (fallback)
```

Then configure IPA to forward non-IPA queries to your existing DNS:
```bash
ipa dnsconfig-mod --forwarder=<YOUR_EXISTING_DNS>
```

### Option B: IPA as Secondary DNS Only

```
# /etc/resolv.conf
search devuatprod.com
nameserver <YOUR_EXISTING_DNS>  # corporate DNS (primary)
nameserver 10.0.0.47            # IPA (secondary)
```

**Caveat**: If your corporate DNS returns NXDOMAIN for `*.devuatprod.com` (which it will, since it doesn't know about IPA-managed zones), most resolver implementations stop at NXDOMAIN and **never try the secondary** IPA server. This will break Kerberos and SSH resolution. Option A is strongly preferred.

### NetworkManager Configuration

```bash
nmcli connection modify <connection> ipv4.dns "10.0.0.47 <YOUR_EXISTING_DNS>"
nmcli connection modify <connection> ipv4.ignore-auto-dns yes
nmcli connection down <connection> && nmcli connection up <connection>
```

## 6. Kerberos Client Configuration

`/etc/krb5.conf` is automatically configured by `ipa-client-install`. Verify:

```ini
[libdefaults]
  default_realm = DEVUATPROD.COM
  dns_lookup_realm = false
  dns_lookup_kdc = true
  rdns = false
  ticket_lifetime = 24h
  renew_lifetime = 7d
  forwardable = true

[realms]
  DEVUATPROD.COM = {
    kdc = ipa.devuatprod.com
    admin_server = ipa.devuatprod.com
  }

[domain_realm]
  .devuatprod.com = DEVUATPROD.COM
  devuatprod.com = DEVUATPROD.COM
```

## 7. Verification Checklist

- [ ] Forward DNS resolves hostnames to IPs
- [ ] Reverse DNS resolves IPs to hostnames
- [ ] All SRV records present for Kerberos, LDAP, kpasswd
- [ ] Kerberos ticket obtained successfully
- [ ] Service principal verified (`kvno host/...`)
- [ ] DNS forwarders configured
- [ ] Reverse zone exists

## Next Steps

Proceed to [Phase 4: Client Enrollment](04-client-enrollment.md).
