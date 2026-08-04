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

    # ejabberd must be able to read the YunoHost-managed certs
    usermod -aG ssl-cert ejabberd || true
}
