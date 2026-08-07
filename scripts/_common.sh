#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# shellcheck disable=SC2034 # app/config_path are consumed by scripts that source this file
config_path=/etc/ejabberd

# Is the coturn app installed on this box? Tests the settings file the
# ynh_app_setting_get helper actually reads (it hard-fails if the file is missing),
# which is both cheaper and more accurate than parsing `yunohost app list`.
_ejabberd_coturn_is_installed() {
    [ -e /etc/yunohost/apps/coturn/settings.yml ]
}

# Can we actually fetch coturn_ynh? `yunohost app install coturn` git-clones it from
# GitHub, and git has no connect timeout of its own: on a box with no (or a black-holed
# IPv6) route out -- CI containers, firewalled servers -- it stalls ~5 minutes before
# failing. Probing first with a hard timeout keeps that stall out of every install.
_ejabberd_coturn_is_reachable() {
    timeout 30 git ls-remote --exit-code "https://github.com/YunoHost-Apps/coturn_ynh" HEAD >/dev/null 2>&1
}

# Renders ejabberd.yml + nginx + well-known host-meta, wires coturn (STUN/TURN)
# and YunoHost cert access. Called (idempotently) by install/upgrade/restore.
#
# shellcheck disable=SC2154 # domain, data_dir are set by the YunoHost helpers environment
_ejabberd_configure() {

    # coturn is a SOFT dependency: scripts/install tries to install it, but a failure
    # there is non-fatal (a github/catalog hiccup must not sink the whole install).
    # When it is absent -- or its settings are unreadable -- turn_secret/turn_port stay
    # empty and conf/ejabberd.yml drops mod_stun_disco entirely (jinja conditional).
    # ejabberd then runs fine; only STUN/TURN advertisement (XEP-0215) is missing.
    # shellcheck disable=SC2034 # turn_host/turn_port/turn_secret feed the jinja template
    turn_host="$domain"
    turn_secret=""
    turn_port=""
    if _ejabberd_coturn_is_installed; then
        turn_secret=$(ynh_app_setting_get --app="coturn" --key=turnserver_pwd) || turn_secret=""
        turn_port=$(ynh_app_setting_get --app="coturn" --key=port_turnserver_tls) || turn_port=""
    fi
    if [ -z "$turn_secret" ] || [ -z "$turn_port" ]; then
        turn_secret=""
        turn_port=""
        ynh_print_warn "coturn is not available: ejabberd will not advertise STUN/TURN (XEP-0215), so audio/video calls between clients behind NAT may fail. Install it later with 'yunohost app install coturn', then re-run 'yunohost app upgrade ejabberd' to pick it up."
    fi

    # Restore custom settings from config panel if any, or setup reasonable default values
    ynh_app_setting_set_default --key=http_upload_size --value="104857600"
    # shellcheck disable=SC2034
    http_upload_size=$(ynh_app_setting_get --key=http_upload_size)

    # XEP-0157 server contact address (config panel field), empty by default
    ynh_app_setting_set_default --key=xmpp_contact_address --value=""
    # shellcheck disable=SC2034
    xmpp_contact_address=$(ynh_app_setting_get --key=xmpp_contact_address)

    ynh_print_info "Adding ejabberd configuration files..."

    mkdir -p "$data_dir/upload"
    chown -R ejabberd:ejabberd "$data_dir"

    # Render ejabberd config. --jinja (not the simple __VAR__ format) because the
    # coturn/mod_stun_disco block needs a conditional; shell variables in scope here
    # ($domain, $port_*, $data_dir, $turn_*, ...) are the jinja context.
    ynh_config_add --jinja --template="ejabberd.yml" --destination="/etc/ejabberd/ejabberd.yml"
    chown root:ejabberd /etc/ejabberd/ejabberd.yml
    chmod 640 /etc/ejabberd/ejabberd.yml

    # Add nginx config: .well-known/host-meta + BOSH/WebSocket proxy to ejabberd's HTTPS listener
    ynh_print_info "Configuring NGINX..."
    ynh_config_add --template="nginx.conf" --destination="/etc/nginx/conf.d/${domain}.d/ejabberd.conf"

    # Content for /.well-known/host-meta (XEP-0156: Discovering Alternative XMPP Connection Methods)
    mkdir -p "/var/www/.well-known/${domain}"
    ynh_config_add --template="well-known_host-meta.xml" --destination="/var/www/.well-known/${domain}/host-meta"
    chmod 644 "/var/www/.well-known/${domain}/host-meta"
    ynh_config_add --template="well-known_host-meta.json" --destination="/var/www/.well-known/${domain}/host-meta.json"
    chmod 644 "/var/www/.well-known/${domain}/host-meta.json"

    # ejabberd must be able to read the YunoHost-managed certs
    usermod -aG ssl-cert ejabberd || true
}

# XEP-0485 (PubSub Server Information): install the ejabberd-contrib module
# mod_pubsub_serverinfo. It is pure Erlang, compiled at install time by erlc (from
# erlang-base, a hard ejabberd dependency -- no build-essential/erlang-dev needed);
# `git` (resources.apt) fetches the ejabberd-contrib sources. `module_install` is a
# live-node command, so this MUST run while ejabberd is up. The enablement persists
# across restarts via ~ejabberd/.ejabberd-modules, so the module is intentionally
# NOT listed in ejabberd.yml -- listing an as-yet-uncompiled module would abort
# startup (chicken-and-egg). Every step is non-fatal: a fetch/compile failure must
# not sink the whole install over one cosmetic, informational XEP.
_ejabberd_install_contrib_modules() {
    ynh_print_info "Installing ejabberd-contrib module mod_pubsub_serverinfo (XEP-0485)..."
    if ! ejabberdctl modules_update_specs; then
        ynh_print_warn "Could not refresh ejabberd-contrib specs; skipping XEP-0485 module."
        return 0
    fi
    # Fresh install -> module_install; already present (upgrade) -> module_upgrade to
    # recompile against the current ejabberd (apt may have bumped it).
    if ejabberdctl modules_installed | grep -q '^mod_pubsub_serverinfo'; then
        ejabberdctl module_upgrade mod_pubsub_serverinfo \
            || ynh_print_warn "Could not upgrade mod_pubsub_serverinfo (XEP-0485)."
    else
        ejabberdctl module_install mod_pubsub_serverinfo \
            || ynh_print_warn "Could not install mod_pubsub_serverinfo (XEP-0485)."
    fi
    return 0
}
