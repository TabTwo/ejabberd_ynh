<h1>
  ejabberd, packaged for YunoHost
</h1>

Robust, scalable and extensible realtime platform (XMPP server)

[![🌐 Official app website](https://img.shields.io/badge/Official_app_website-darkgreen?style=for-the-badge)](https://www.ejabberd.im/)

## Overview

[ejabberd](https://www.ejabberd.im/) is an XMPP server written in Erlang. This package
integrates it with YunoHost: accounts come from YunoHost's LDAP directory (permission-gated),
certificates are the ones YunoHost already manages, and nginx serves the
`.well-known` discovery endpoints plus the BOSH and WebSocket entry points.

Out of the box it passes the [XMPP Compliance Suites 2023](https://xmpp.org/extensions/xep-0479.html)
at 100% — including XEP-0368 direct TLS, XEP-0363 HTTP upload, XEP-0215 external
STUN/TURN discovery and XEP-0485 PubSub server information — and it publishes its own
DNS records, so `yunohost domain dns push` sets up the `_xmpp` and `_xmpps` SRV entries
for you.

**Requires YunoHost 13 (Debian 13 / Trixie) or newer.** The configuration uses
ejabberd 24.12 features that the Bookworm package does not have, so Bookworm is
deliberately unsupported.

**Cannot be installed alongside another XMPP server** (`prosody`, `metronome`) — they
compete for ports 5222 and 5269.

## Documentation

- Official documentation: <https://docs.ejabberd.im/>
- Admin notes for this package: [`doc/ADMIN.md`](doc/ADMIN.md)
- Before you install: [`doc/PRE_INSTALL.md`](doc/PRE_INSTALL.md)

## 📦 Developer info

Pull requests are welcome and should target the `testing` branch.

The `testing` branch can be tested using:

```
# fresh install:
sudo yunohost app install https://github.com/YunoHost-Apps/ejabberd_ynh/tree/testing

# upgrade an existing install:
sudo yunohost app upgrade ejabberd -u https://github.com/YunoHost-Apps/ejabberd_ynh/tree/testing
```

### 📚 App packaging documentation

Please see <https://doc.yunohost.org/packaging_apps> for more information.
