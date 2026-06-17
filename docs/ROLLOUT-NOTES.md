# Production rollout notes

This project must not contain real server addresses, tokens, domains or private inventory.

## Runtime config

Copy the example file and edit it on each server:

```bash
sudo mkdir -p /etc/vps-hardening
sudo cp templates/vps-hardening.env.example /etc/vps-hardening/vps-hardening.env
sudo nano /etc/vps-hardening/vps-hardening.env
```

Important variables:

```bash
VPSH_IGNORE_IPS="127.0.0.1/8 ::1"
VPSH_BLOCKTYPE="deny"
VPSH_SSH_PORT="auto"
VPSH_ENABLE_NGINX_JAILS="true"
VPSH_ENABLE_RECIDIVE="true"
VPSH_LOGROTATE_ROTATE="14"
```

## Single server flow

```bash
sudo vps-hardening install
sudo vps-hardening doctor
sudo vps-hardening fail2ban
sudo vps-hardening logrotate
sudo vps-hardening clean-reject
sudo vps-hardening status
```

## Notes

- `deny` is preferred for quiet UFW blocks.
- `clean-reject` removes old UFW REJECT rules after switching to deny.
- `clear-fail2ban-db` is an emergency command when old bans keep returning from Fail2Ban state.
- Keep SSH, 80 and 443 rules aligned with the role of the server.
