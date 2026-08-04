# ejabberd_ynh — design spec

**Date:** 2026-08-04
**Goal:** A catalog-submittable YunoHost app that installs **ejabberd** as an XMPP server, integrated with YunoHost (LDAP/SSO, certs, DNS, permissions), passing the XMPP Compliance Suite. XMPP-only for v1; the Matrix gateway is explicitly out of scope (deferred to a later version).

**Status:** approved design (brainstorming). Next: implementation plan (writing-plans).

## Context & why

- There is **no existing `ejabberd_ynh`** (not on YunoHost-Apps, no forks). This is a from-scratch package.
- `project-ejabberd`'s long-term goal is "replace prosody and synapse". The [bake-off decision](../../2026-08-04-ejabberd-vs-prosody13-bakeoff.md) concluded: for XMPP, Prosody 13 is ahead, and ejabberd's unique draw (native Matrix gateway) is broken on Debian/OTP-27 (ejabberd #4602 / Debian #1143612). So **v1 is XMPP-only**, a clean foundation; Matrix is added later once that bug ships fixed.
- **Models:** `YunoHost/example_ynh` (skeleton / current conventions) + `prosody_ynh` (proven XMPP↔YunoHost integration) + `metronome_ynh` (secondary reference). **Approach = hybrid:** example_ynh skeleton, XMPP integration patterns lifted from prosody_ynh, ejabberd-specific config/logic written fresh.

## Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| ejabberd source | **Debian package** (`ejabberd`, 24.12 on Trixie) | Idiomatic YunoHost packaging; auto security updates |
| Auth | **LDAP** (YunoHost directory, permission-gated) | SSO/user integration. PLAIN-only (same as Prosody; see YunoHost/issues#2829) |
| Storage | **mnesia** (built-in) | No SQL dependency; fine at small scale; MAM works on mnesia |
| TLS certs | **YunoHost-managed** (`/etc/yunohost/certs/__DOMAIN__/`) | Not ejabberd's ACME; YunoHost owns cert lifecycle. Reload ejabberd on renewal |
| STUN/TURN | **External coturn** (`coturn_ynh`, auto-installed if absent) | The shared TURN server across YunoHost apps; ejabberd advertises it via `mod_stun_disco` (XEP-0215) using coturn's REST secret — mirrors prosody_ynh exactly |
| Matrix gateway | **out of scope (v1)** | Broken on Debian/OTP-27; revisit after ejabberd#4602 ships |
| Coexistence | **cannot co-install with prosody_ynh/metronome_ynh** | Port 5222/5269 clash — documented in the app description |

## Architecture

Single ejabberd host = the YunoHost domain `__DOMAIN__`, with service subdomains `conference.`, `pubsub.`, `upload.`, `proxy.__DOMAIN__`. ejabberd terminates XMPP (c2s/s2s, STARTTLS + direct-TLS) and serves its own HTTP (upload/BOSH/WS/admin) on TLS ports; **nginx** serves `/.well-known/host-meta` (XEP-0156) and proxies BOSH/WebSocket, exactly as prosody_ynh does. YunoHost provides LDAP, certs, the firewall (declared ports), and DNS suggestions (via the custom_dns_rules hook).

### Listeners / ports (manifest `resources.ports`)
| purpose | port | notes |
|---|---|---|
| c2s STARTTLS | 5222 | `ejabberd_c2s`, starttls_required |
| c2s direct-TLS (XEP-0368) | 5223 | `tls: true` — must have a cert (the trap prosody hit) |
| s2s STARTTLS | 5269 | `ejabberd_s2s_in` |
| s2s direct-TLS (XEP-0368) | 5270 | optional but nice; needs cert |
| HTTPS (upload/BOSH/WS/api) | 5443 | `ejabberd_http` tls |
| HTTP (admin/local) | 5280 | localhost-bound; admin + optional acme |
| proxy65 (XEP-0065) | 7777 | `mod_proxy65` bytestreams |

**STUN/TURN ports are NOT owned by ejabberd** — the external **coturn** app provides `3478` + its relay range. ejabberd only *advertises* coturn to clients via `mod_stun_disco`. (This is why we depend on coturn rather than run ejabberd's built-in `ejabberd_stun`: it keeps a single shared TURN server on the box and off ejabberd's firewall surface.)

### DNS (`hooks/custom_dns_rules`) — relative names (Porkbun lesson)
- SRV: `_xmpp-client._tcp` 5222, `_xmpp-server._tcp` 5269, `_xmpps-client._tcp` 5223, `_xmpps-server._tcp` 5270.
- CNAME: `conference`, `pubsub`, `upload`, `proxy` → `__DOMAIN__`.
- TLSA: optional/documented (YunoHost cert renewal rotates keys → `3 1 1` churns; align with [[project_smtp_dane]] thinking — leave off by default).

## File structure

```
manifest.toml                     packaging v2: id, version, install args (domain),
                                  resources.ports/apt(ejabberd)/permissions(main+admin)
scripts/_common.sh                shared: _ejabberd_config() (renders ejabberd.yml + cert wiring),
                                  reads coturn settings (turnserver_pwd, port), helpers
scripts/install                   provision, apt, auto-install coturn if absent, render config,
                                  permissions, dns hook, nginx, start
scripts/remove                    stop, purge config, remove nginx/dns hook
scripts/upgrade                   re-render config idempotently; migrate settings
scripts/backup                    mnesia spool (/var/lib/ejabberd) + /etc/ejabberd + settings
scripts/restore                   restore spool + config + permissions
conf/ejabberd.yml                 templated (__DOMAIN__, __PORTS__, cert paths, LDAP filter,
                                  modules, listeners) — the heart of it
conf/nginx.conf                   .well-known/host-meta + BOSH(/http-bind) + WS(/ws) proxy to 5443
conf/well-known_host-meta.xml     XEP-0156 connection methods
hooks/custom_dns_rules            SRV + CNAME (relative names)
config_panel.toml                 registration on/off, upload size/quota/expiry, MUC defaults
tests.toml                        package_check: install/remove/upgrade/backup-restore/multi-instance=false
doc/{DESCRIPTION,ADMIN,PRE_INSTALL}.md   incl. the "no coexistence with prosody/metronome" note
LICENSE (AGPL-3.0, matching ejabberd) · README.md (generated) · manifest screenshots
```

## ejabberd config specifics (`conf/ejabberd.yml`)

- **hosts:** `[__DOMAIN__]`.
- **auth:** `auth_method: [ldap]`; `ldap_servers: [localhost]`; `ldap_base: "ou=users,dc=yunohost,dc=org"`; `ldap_uids: [{ "uid": "%u" }]` (+ mail); `ldap_filter: "(permission=cn=__APP__.main,ou=permission,dc=yunohost,dc=org)"` — mirrors prosody_ynh's permission gate. `auth_password_format: scram` is moot under LDAP (bind → PLAIN).
- **certfiles:** `["/etc/yunohost/certs/__DOMAIN__/crt.pem", "/etc/yunohost/certs/__DOMAIN__/key.pem"]`; reload ejabberd on YunoHost cert renewal (cert-renew hook / `ejabberdctl reload_config`).
- **TLS hardening:** `TLS_OPTIONS` (no sslv3/tls1/1.1), strong ciphers, `s2s_use_starttls: required`, `disable_sasl_mechanisms: [digest-md5, X-OAUTH2]`.
- **modules (compliance set, verified on ejabberdtest):** mod_mam (mnesia, `default: always`), mod_carboncopy, mod_client_state, mod_stream_mgmt, mod_muc (+`mam: true`), mod_muc_admin, mod_http_upload (docroot under data dir, size from config_panel), mod_proxy65, mod_push (+keepalive), mod_pubsub (flat+pep), mod_blocking, mod_privacy, mod_ping, mod_disco, mod_vcard(+xupdate), mod_adhoc, mod_version, mod_last, mod_offline, mod_stun_disco (advertises the **external coturn** via XEP-0215 using coturn's REST secret), mod_s2s_bidi, mod_s2s_dialback. **XEP-0157 contact info** — confirm ejabberd mechanism during implementation (top-level `contact`/`mod_disco` info).
- **listeners:** per the ports table; HTTP request_handlers `/upload`→mod_http_upload, `/bosh`→mod_bosh, `/ws`→ejabberd_http_ws, `/admin`→ejabberd_web_admin (localhost).

## Testing / definition of done

- `package_check` (tests.toml) green: install, remove, upgrade-from-self, backup/restore, change-URL N/A, multi-instance=false.
- On a fresh **YunoHost 13**: installs, ejabberd runs, a YunoHost user logs in over XMPP (LDAP), server **federates**, and **passes the XMPP Compliance Suite** (compliance.conversations.im), direct-TLS 5223 handshake succeeds (cert wired — the prosody trap avoided).
- Backup → remove → restore round-trips (accounts/roster/MAM in mnesia survive).

## Out of scope (v1) — documented as future work
- **Matrix gateway** (`mod_matrix_gw`) — after ejabberd#4602 / Debian#1143612.
- **SQL backend** (postgres/mysql) — mnesia is enough at target scale.
- **SCRAM / usable channel binding** — blocked platform-wide by YunoHost LDAP (YunoHost/issues#2829); not app-solvable.
- Multi-domain, cluster.

## Open items to resolve during implementation
- ejabberd XEP-0157 contact-info exact config.
- coturn wiring: read `turnserver_pwd` + `port_turnserver_tls` from the coturn app and map to `mod_stun_disco` `services` (host/port/type/transport/secret) — confirm exact shape during implementation.
- Whether to expose the ejabberd web admin (localhost only vs a YunoHost SSO-gated path).
- Cert-renewal reload mechanism (hook name / conf_regen vs YunoHost cert hook).
