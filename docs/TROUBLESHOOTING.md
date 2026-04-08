# TROUBLESHOOTING / УСТРАНЕНИЕ НЕПОЛАДОК

## EN

### `sshd -t` failed
- Review `/etc/ssh/sshd_config.d/99-vps-hardening.conf`.
- Run `sudo sshd -t` manually.
- Restore previous config using `vps-hardening rollback`.

### Fail2Ban jail doesn't start
- Run `sudo fail2ban-client -t`.
- Check `/etc/fail2ban/jail.local` and `/var/log/fail2ban.log`.

### UFW risk of lockout
- Ensure rule `OpenSSH` exists before enabling UFW.
- Use cloud console/KVM if network access is broken.

### Logs
- Toolkit log: `/var/log/vps-hardening.log`
- UFW log: `/var/log/ufw.log`
- Fail2Ban log: `/var/log/fail2ban.log`

## RU

### Ошибка `sshd -t`
- Проверьте `/etc/ssh/sshd_config.d/99-vps-hardening.conf`.
- Выполните `sudo sshd -t` вручную.
- Восстановите конфиг через `vps-hardening rollback`.

### Fail2Ban не запускается
- Выполните `sudo fail2ban-client -t`.
- Проверьте `/etc/fail2ban/jail.local` и `/var/log/fail2ban.log`.

### Риск блокировки при UFW
- Убедитесь, что правило `OpenSSH` существует до `ufw enable`.
- При потере доступа используйте консоль провайдера/KVM.

### Логи
- Лог toolkit: `/var/log/vps-hardening.log`
- Лог UFW: `/var/log/ufw.log`
- Лог Fail2Ban: `/var/log/fail2ban.log`
