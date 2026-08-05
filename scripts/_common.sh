#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# shellcheck disable=SC2034 # app/config_path are consumed by scripts that source this file
app=ejabberd
config_path=/etc/ejabberd

# Renders ejabberd.yml + nginx + well-known host-meta, wires coturn (STUN/TURN)
# and YunoHost cert access. Called (idempotently) by install/upgrade/restore.
#
# shellcheck disable=SC2154 # domain, data_dir are set by the YunoHost helpers environment
_ejabberd_configure() {

    # coturn (auto-installed by scripts/install if absent)
    # shellcheck disable=SC2034 # turn_host/turn_port/turn_secret feed ynh_config_add substitution
    turn_secret=$(ynh_app_setting_get --app="coturn" --key=turnserver_pwd)
    # shellcheck disable=SC2034
    turn_port=$(ynh_app_setting_get --app="coturn" --key=port_turnserver_tls)
    # shellcheck disable=SC2034
    turn_host="$domain"

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

    # Render ejabberd config (ynh_config_add substitutes __PORT_CLIENT__ <- $port_client, etc.)
    ynh_config_add --template="ejabberd.yml" --destination="/etc/ejabberd/ejabberd.yml"
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
