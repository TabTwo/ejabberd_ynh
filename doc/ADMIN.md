# ejabberd Administration Guide

## Basic Administration

### Using ejabberdctl

The `ejabberdctl` command is the primary tool for administering ejabberd. It can be used to:

- Manage user accounts
- Monitor server status
- Query statistics
- Configure runtime settings

Common `ejabberdctl` commands:

```bash
# Register a new user
ejabberdctl register username domain password

# Unregister a user
ejabberdctl unregister username domain

# Change a user's password
ejabberdctl change_password username domain newpassword

# List connected users
ejabberdctl connected_users

# Show server status
ejabberdctl status

# Dump database to file
ejabberdctl dump_table table_name > /tmp/dump.txt
```

For a complete list of available commands, see the [ejabberdctl documentation](https://docs.ejabberd.im/admin/guide/managing/).

## Data Storage

### Message Archive Management (MAM)

User messages and conversation history are stored in ejabberd's internal database (mnesia) if Message Archive Management is enabled in the configuration panel.

- **Location**: `/var/lib/ejabberd/`
- **Database**: ejabberd uses Mnesia (Erlang term storage) by default

To access or backup archived messages, refer to the [MAM documentation](https://docs.ejabberd.im/admin/configuration/modules/mod_mam/).

### Offline Messages

If offline message storage is enabled, messages sent to users who are currently offline will be queued and delivered when they reconnect.

### Mnesia Database Location

All user data, rosters (contact lists), offline messages, and archives are stored in:

```
/var/lib/ejabberd/
```

**Important**: Do not manually modify files in this directory. Always use `ejabberdctl` or the administration interface for changes.

## Certificate Management

YunoHost automatically manages SSL/TLS certificates for ejabberd:

- Certificates are installed and renewed automatically via Let's Encrypt
- When a certificate is renewed, ejabberd is notified via the `post_cert_update` hook
- The hook reloads the certificate configuration in ejabberd without requiring a restart

**Manual certificate reload** (if needed):

```bash
ejabberdctl reload_config
```

## Performance Tuning

For large deployments or high user counts, consider:

1. **Database**: Evaluate whether to switch to external database backends (PostgreSQL, MySQL)
2. **Cluster**: Set up ejabberd clustering across multiple servers
3. **Resource Limits**: Adjust connection limits and queue sizes in `/etc/ejabberd/ejabberd.yml`

See the [ejabberd performance guide](https://docs.ejabberd.im/admin/guide/performance/) for details.

## Monitoring and Logging

### Log Files

Log output is available via the system journal:

```bash
journalctl -u ejabberd -f
```

### Statistics

Monitor server health:

```bash
# Get server statistics
ejabberdctl stats

# Check specific counters
ejabberdctl stats online_users
ejabberdctl stats registered_users
```

## Backup and Recovery

### Backup Mnesia Database

```bash
# Stop ejabberd
systemctl stop ejabberd

# Backup the database directory
tar czf /backup/ejabberd-backup-$(date +%Y%m%d).tar.gz /var/lib/ejabberd/

# Start ejabberd
systemctl start ejabberd
```

### Restoring from Backup

```bash
# Stop ejabberd
systemctl stop ejabberd

# Restore from backup
tar xzf /backup/ejabberd-backup-YYYYMMDD.tar.gz -C /

# Start ejabberd
systemctl start ejabberd
```

## Further Resources

- **Official Administration Guide**: https://docs.ejabberd.im/admin/guide/
- **Configuration Reference**: https://docs.ejabberd.im/admin/configuration/
- **Module Documentation**: https://docs.ejabberd.im/admin/configuration/modules/
