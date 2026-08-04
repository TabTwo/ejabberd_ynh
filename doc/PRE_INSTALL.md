# Before Installing ejabberd

## Critical: Port Conflicts

**Do NOT install ejabberd if you already have Prosody or Metronome running**, as they all require the same XMPP network ports and **cannot coexist on the same server**:

- **Prosody**: Manages ports 5222, 5269
- **Metronome**: Manages ports 5222, 5269
- **ejabberd**: Requires ports 5222, 5269, 5223, 5270, and 5443

**If you have another XMPP server installed, uninstall it first.**

## DNS Configuration

After installation, YunoHost will suggest DNS records that you should add to your domain:

- **SRV records** for XMPP service discovery (e.g., `_xmpp-client._tcp`, `_xmpp-server._tcp`)
- **CNAME or A records** pointing to your YunoHost server

These DNS records are essential for:
- XMPP clients to discover your server automatically
- Other XMPP servers to establish federation with your server
- Proper SRV/TLSA/DANE validation for secure communications

YunoHost will provide the exact DNS entries needed. You may need to wait for DNS propagation (up to 24 hours) before all XMPP functionality is fully operational.

## Requirements

- A valid domain name (required for XMPP federation and certificates)
- At least 256MB RAM (see manifest for details)
- At least 50MB disk space
- No other XMPP server running
