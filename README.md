# vps-hardening-toolkit

Production-oriented Bash CLI toolkit for baseline Ubuntu VPS hardening with one interface.

## Quick install

> Replace `your-org` with your GitHub org/user.

```bash
curl -fsSL https://raw.githubusercontent.com/your-org/vps-hardening-toolkit/main/install.sh | sudo bash
```

or

```bash
wget -qO- https://raw.githubusercontent.com/your-org/vps-hardening-toolkit/main/install.sh | sudo bash
```

After install:

```bash
sudo vps-hardening doctor
sudo vps-hardening all
```

## What the project does

- SSH hardening with safe key onboarding flow (generate/paste/skip), pre-checks and explicit confirmation before restart.
- Fail2Ban install and safe managed SSH jail configuration.
- UFW setup with OpenSSH, Nginx rules, Cloudflare ranges and custom trusted IPs.
- Backups with timestamp and rollback command.
- Idempotent reruns and centralized logging.

## CLI

```bash
vps-hardening help
vps-hardening install
vps-hardening ssh
vps-hardening fail2ban
vps-hardening ufw
vps-hardening all
vps-hardening status
vps-hardening doctor
vps-hardening rollback
```

## Safety guarantees

- Password SSH login is not disabled until at least one valid key exists.
- No SSH restart without explicit yes/no confirmation.
- No UFW enable without explicit yes/no confirmation.
- Dangerous actions are stopped if validation fails (`sshd -t`, `fail2ban-client -t`).

## Supported OS

- Ubuntu 20.04
- Ubuntu 22.04
- Ubuntu 24.04

## Documentation

- [RU/EN Quick Install](docs/QUICK-INSTALL.md)
- [RU/EN Manual Install](docs/MANUAL-INSTALL.md)
- [RU/EN Usage](docs/USAGE.md)
- [RU/EN Troubleshooting](docs/TROUBLESHOOTING.md)

## Project structure

```text
bin/        # CLI entrypoint
lib/        # hardening modules
templates/  # reference templates
docs/       # bilingual docs
```

## Logging

Execution logs are written to:

```text
/var/log/vps-hardening.log
```
