# ejabberd vs Prosody 13 — bake-off & decision

**Date:** 2026-08-04
**Question:** Should project-ejabberd pursue an `ejabberd_ynh` app to **replace Prosody (XMPP) and Synapse (Matrix)** with a single server on YunoHost?
**Method:** two fresh Debian 13 (Trixie) VMs — `ejabberdtest.mayer.rocks` (ejabberd) and `yunotest.mayer.rocks` (YunoHost 13.0.5 + prosody_ynh). Probed pre-auth stream features (SASL/SASL2/channel-binding), disco, module config, and a live XMPP→Matrix test. Both boxes remain up and reproducible.

## TL;DR / recommendation

**Do not rush `ejabberd_ynh` to replace prosody+synapse yet.** The bake-off says:

- **For XMPP, replacing Prosody would be a regression today.** On Debian Trixie, Prosody 13 is **SASL2-complete** (SASL2 + Bind2 + FAST + channel-binding, via bundled modules), while Debian's **ejabberd 24.12 cannot do SASL2** — its `mod_bind2` is not packaged. Prosody is also already the mature, native YunoHost XMPP app.
- **ejabberd's one unique draw is the native Matrix gateway** (`mod_matrix_gw`) — the "replace Synapse" half. It genuinely works (an XMPP→Matrix DM was delivered end-to-end), **but only on Erlang/OTP 26**. Debian Trixie builds ejabberd against **OTP 27**, which breaks the gateway entirely (see [ejabberd#4602](https://github.com/processone/ejabberd/issues/4602)). It is also still experimental (room support is rough).

**So:** keep Prosody 13 for XMPP (and land the SASL2 default-modules PR below). Treat ejabberd-for-Matrix as a **watch item**: revisit once (a) the OTP-27 `mod_matrix_gw` bug is fixed and shipped, and (b) the gateway matures past experimental. The "one server for XMPP+Matrix" vision is real but premature on the current Debian stack.

## The comparison (verified)

| axis | ejabberd 24.12 (Debian, internal SCRAM auth) | Prosody 13.0.1 (prosody_ynh, LDAP auth) |
|---|---|---|
| **SASL2 (XEP-0388)** | ❌ code present, but `mod_bind2` not in Debian pkg → not advertised | ✅ bundled `mod_sasl2/_bind2/_sm/_fast` — enable + restart |
| **Bind2 (XEP-0386)** | ❌ | ✅ |
| **channel binding / tls-exporter (RFC 9266)** | ✅ usable (SCRAM-256-PLUS) | ✅ advertised, but **unusable** (no SCRAM-`*`-PLUS) |
| **SCRAM** | SCRAM-SHA-256(-PLUS) after `auth_scram_hash: sha256` | **PLAIN only** — LDAP backend cannot do SCRAM |
| SASL-SSDP (XEP-0474) | `mod_sasl_ssdp` (rockspec) | bundled `mod_sasl_ssdp` |
| MAM / carbons / CSI / smacks / push | ✅ (mam:2, carboncopy, client_state, stream_mgmt, push) | ✅ (mam+muc_mam, csi_battery_saver, smacks, cloud_notify) |
| MUC / PubSub-PEP / HTTP-upload / proxy65 | ✅ (proxy65 native) | ✅ (http_file_share; proxy via TURN) |
| BOSH / WebSocket / A-V | BOSH+WS (5443), STUN | BOSH, WebSocket, TURN (coturn/turn_external) |
| **native Matrix gateway** | ✅ `mod_matrix_gw` (works on OTP 26; broken on OTP 27) | ✖ none |
| built-in ACME | ✅ | via YunoHost certs |
| idle RAM | ~114 MB (beam) | Lua (lighter; not measured) |
| YunoHost integration | `ejabberd_ynh` exists, untested here | mature, native (`prosody_ynh`) |

## Key findings

1. **SASL2 is Prosody 13's win.** The reason to want Prosody 13 (SASL2 + modern channel binding) is real and turnkey: enabling `sasl2, sasl2_bind2, sasl2_sm, sasl2_fast, sasl_ssdp` and restarting made yunotest advertise SASL2 + Bind2 + channel-binding + inline smacks/CSI. Debian's ejabberd can't match this (missing `mod_bind2`).

2. **SCRAM is blocked by YunoHost's LDAP auth — on *both* servers.** With `authentication = "ldap"`, the password lives in LDAP, so no server can offer SCRAM → PLAIN only → channel binding is advertised but not usable. ejabberd only showed SCRAM-256-PLUS here because it ran on *internal* (non-YunoHost) auth. **This is a YunoHost architectural limit, not a Prosody-vs-ejabberd difference** — and the highest-value "give back to YunoHost" target (expose SCRAM-capable credentials to the XMPP server, or offer an internal-auth option).

3. **ejabberd's Matrix gateway works but is fragile.** With a real cert on :8448 and `mod_matrix_gw`, an XMPP account delivered a DM to a real `@user:mayer.rocks` Matrix account (federation via deck's Synapse). But on Debian/OTP-27 every outbound event crashes in `content_hash` (`misc:json_encode_with_kv_lists` vs OTP 27's native `json`). Filed upstream ([#4602](https://github.com/processone/ejabberd/issues/4602), follow-up to closed #4244) and a Debian bug is drafted.

## Consequences for project-ejabberd

- **Don't frame it as "replace Prosody."** For pure XMPP on YunoHost, Prosody 13 is ahead (SASL2) and already native. Replacing it buys nothing and loses SASL2 until Debian ejabberd ships `mod_bind2`.
- **The compelling scope is "one server that also reaches Matrix."** That hinges entirely on `mod_matrix_gw` becoming (a) OTP-27-safe and (b) non-experimental. Until then an `ejabberd_ynh` would either ship a broken Matrix gateway (Debian/OTP-27) or need a bundled-OTP build (diverging from the YunoHost/Debian packaging model).
- **Bridges caveat:** even a working `mod_matrix_gw` only federates XMPP↔Matrix; the mautrix (Signal/WhatsApp) bridges currently hanging off Synapse would still need XMPP-native transports — a separate migration.

## Recommended next steps

1. **prosody_ynh PR (do now):** add `sasl2, sasl2_bind2, sasl2_sm, sasl2_fast, sasl_ssdp` to the default `modules_enabled` → Prosody 13 SASL2-complete out of the box. Tested working on yunotest.
2. **Chase the SCRAM/LDAP limit** (the real YunoHost problem): investigate whether YunoHost can give the XMPP server SCRAM-capable credentials, or an opt-in internal-auth mode. This unlocks usable channel binding for *any* server.
3. **Keep project-ejabberd as a watch item** gated on ejabberd#4602 (OTP-27 fix) + `mod_matrix_gw` leaving experimental. Re-run this bake-off's Matrix test then.
4. Optionally stand up `ejabberd_ynh` (LDAP) to confirm it is also PLAIN-limited (expected), closing the apples-to-apples gap.

## Evidence / reproduction
- Prosody probe: STARTTLS stream-features on `yunotest.mayer.rocks:5222`; config `/etc/prosody/conf.d/yunotest.mayer.rocks.cfg.lua`.
- ejabberd probe: direct-TLS `ejabberdtest.mayer.rocks:5223`; disco via a slixmpp login; Matrix via `mod_matrix_gw` on :8448.
- ProcessOne build test: `ejabberd/ecs:latest` (26.7.0, OTP 26) delivered the XMPP→Matrix DM that the Debian 24.12/OTP-27 build could not.
