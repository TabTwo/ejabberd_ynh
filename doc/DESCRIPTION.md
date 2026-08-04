# ejabberd

ejabberd is a robust, scalable, and modular XMPP (Extensible Messaging and Presence Protocol) server. It is written in Erlang and designed for high availability and performance.

## Key Features

- **XMPP Compliance**: Full support for XMPP standards (RFC 6120, RFC 6121, RFC 6122)
- **Scalability**: Horizontally scalable architecture supporting millions of concurrent users
- **Modular Design**: Pluggable modules for extensibility
- **LDAP Authentication**: User authentication via YunoHost's LDAP directory
- **Message Archive Management (MAM)**: Optional long-term message storage
- **Multi-Domain Support**: Single installation can serve multiple XMPP domains
- **Security**: Built-in support for TLS/SSL, STARTTLS, and SASL authentication

## Integration with YunoHost

This installation of ejabberd authenticates users through YunoHost's LDAP directory. This means:
- Users authenticate with their YunoHost credentials
- User accounts are managed centrally through YunoHost
- Administrators can manage XMPP access through YunoHost's user management interface

## Important: Port Conflicts

**ejabberd cannot be co-installed with Prosody or Metronome XMPP servers** as they use the same network ports:
- **Client connection port**: 5222/TCP
- **Server federation port**: 5269/TCP

If you have another XMPP server installed, uninstall it before installing ejabberd.

## Audio/Video Support

The YunoHost ejabberd package automatically installs and configures **coturn** to provide NAT traversal and TURN (Traversal Using Relays around NAT) relay services for audio and video communications.

## Additional Resources

- **Official Documentation**: https://docs.ejabberd.im/
- **Official Website**: https://www.ejabberd.im/
- **XMPP Standards**: https://xmpp.org/
