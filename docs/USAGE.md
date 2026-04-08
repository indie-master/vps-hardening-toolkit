# USAGE / ИСПОЛЬЗОВАНИЕ

## EN

### Core commands
- `vps-hardening doctor` — environment checks.
- `vps-hardening all` — run SSH + Fail2Ban + UFW.
- `vps-hardening rollback` — restore one config from backup list.

### SSH access safety
- Do not confirm password disable until you tested key login in a second session.
- Toolkit refuses disabling password auth if no valid key is present.

### Telegram private key export
When key is generated on the server, you may export private key via Telegram Bot API.
Required:
- `BOT_TOKEN`
- `CHAT_ID`

The tool sends the key as a document to your chat.

### Rollback
Backups are in `/var/backups/vps-hardening`.
Command `vps-hardening rollback` shows backups and restores selected config.

## RU

### Основные команды
- `vps-hardening doctor` — проверка окружения.
- `vps-hardening all` — запуск SSH + Fail2Ban + UFW.
- `vps-hardening rollback` — восстановление конфига из списка backup.

### Как не потерять SSH доступ
- Не подтверждайте отключение пароля, пока не проверили вход по ключу во второй сессии.
- Инструмент не отключит парольный вход, если нет валидного ключа.

### Telegram экспорт приватного ключа
При генерации ключа на сервере можно отправить приватный ключ через Telegram Bot API.
Нужны:
- `BOT_TOKEN`
- `CHAT_ID`

Ключ отправляется как документ в ваш чат.

### Rollback
Бэкапы лежат в `/var/backups/vps-hardening`.
Команда `vps-hardening rollback` покажет список и восстановит выбранный файл.
