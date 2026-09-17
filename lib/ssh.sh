#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${VPS_HARDENING_SSH_SH:-}" ]]; then return 0; fi
VPS_HARDENING_SSH_SH=1
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
readonly SSH_CONFIG="/etc/ssh/sshd_config"
readonly SSH_DROPIN_DIR="/etc/ssh/sshd_config.d"
readonly SSH_HARDENING_DROPIN="/etc/ssh/sshd_config.d/00-vps-hardening.conf"
readonly SSH_KEY_DIR="/root/.ssh/vps-hardening"

ssh::ensure_permissions() { mkdir -p /root/.ssh; chmod 700 /root/.ssh; chown root:root /root/.ssh; touch /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; chown root:root /root/.ssh/authorized_keys; log::ok "SSH permissions fixed for /root/.ssh and authorized_keys."; }
ssh::has_valid_root_key() { [[ -s /root/.ssh/authorized_keys ]] && grep -Eq '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp)' /root/.ssh/authorized_keys; }
ssh::manual_key_add() { log::info "Paste your public key (single line), then press Enter:"; local pubkey; read -r pubkey; [[ "$pubkey" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp)\  ]] || { log::error "Invalid SSH public key format."; return 1; }; printf '%s\n' "$pubkey" >> /root/.ssh/authorized_keys; sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys; log::ok "Public key added."; }
ssh::generate_keypair() { local ts key; mkdir -p "$SSH_KEY_DIR"; chmod 700 "$SSH_KEY_DIR"; ts="$(date '+%Y%m%d-%H%M%S')"; key="$SSH_KEY_DIR/root-ed25519-${ts}"; ssh-keygen -t ed25519 -a 100 -N '' -C "vps-hardening-${ts}" -f "$key" >/dev/null; chmod 600 "$key"; chmod 644 "$key.pub"; cat "$key.pub" >> /root/.ssh/authorized_keys; sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys; log::ok "Generated and installed key pair: $key"; }
ssh::set_sshd_option() { local file="$1" key="$2" value="$3" tmp; tmp="$(mktemp)"; awk -v key="$key" -v value="$value" 'BEGIN{IGNORECASE=1;done=0} {if($0~"^[[:space:]]*#?[[:space:]]*"key"([[:space:]]+|$)"){if(!done){print key" "value;done=1};next} print} END{if(!done)print key" "value}' "$file" > "$tmp"; cat "$tmp" > "$file"; rm -f "$tmp"; }
ssh::dropins_supported() { [[ -d "$SSH_DROPIN_DIR" ]] && grep -Eiq '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d/\*\.conf' "$SSH_CONFIG"; }
ssh::apply_sshd_hardening() { fs::backup_file "$SSH_CONFIG"; if ssh::dropins_supported; then [[ -f "$SSH_HARDENING_DROPIN" ]] && fs::backup_file "$SSH_HARDENING_DROPIN"; cat > "$SSH_HARDENING_DROPIN" <<'CONF'
# Managed by vps-hardening-toolkit
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
CONF
chmod 644 "$SSH_HARDENING_DROPIN"; log::ok "Updated SSH hardening drop-in: $SSH_HARDENING_DROPIN"; else ssh::set_sshd_option "$SSH_CONFIG" PasswordAuthentication no; ssh::set_sshd_option "$SSH_CONFIG" KbdInteractiveAuthentication no; ssh::set_sshd_option "$SSH_CONFIG" PubkeyAuthentication yes; ssh::set_sshd_option "$SSH_CONFIG" PermitRootLogin prohibit-password; log::ok "Updated SSH config in place: $SSH_CONFIG"; fi; }
ssh::effective_value() { local key="$1"; sshd -T 2>/dev/null | awk -v key="${key,,}" '$1==key{v=$2} END{if(v!="")print v}'; }
ssh::verify_effective_hardening() { local p k pk r; p="$(ssh::effective_value passwordauthentication)"; k="$(ssh::effective_value kbdinteractiveauthentication)"; pk="$(ssh::effective_value pubkeyauthentication)"; r="$(ssh::effective_value permitrootlogin)"; [[ "$p" == no ]] || return 1; [[ "$k" == no ]] || return 1; [[ "$pk" == yes ]] || return 1; [[ "$r" == prohibit-password || "$r" == without-password ]] || return 1; }
ssh::configure() { require_root; ssh::ensure_permissions; printf '\nSSH key setup options:\n1) Generate ed25519 key pair on server\n2) Paste existing public key manually\n3) Skip key actions\n'; local a; read -r -p "Choose option [1-3]: " a; case "$a" in 1) ssh::generate_keypair;; 2) ssh::manual_key_add;; *) log::info "Skipping SSH key setup.";; esac; ssh::ensure_permissions; ssh::has_valid_root_key || { log::warn "No valid SSH key found; password authentication will not be disabled."; return 0; }; prompt::yes_no "Disable SSH password authentication and apply hardened settings?" "no" || return 0; ssh::apply_sshd_hardening; sshd -t || { log::error "sshd configuration test failed; SSH will not be restarted."; return 1; }; ssh::verify_effective_hardening || { log::error "Effective sshd settings do not match requested hardening; SSH will not be restarted."; return 1; }; log::ok "sshd syntax and effective hardening checks passed."; prompt::yes_no "Restart SSH service now?" "no" || return 0; if systemctl list-unit-files | grep -q '^ssh\.service'; then svc::restart_and_check ssh; else svc::restart_and_check sshd; fi; }
ssh::status() { [[ -f "$SSH_CONFIG" ]] || { log::warn "SSH config not found."; return 0; }; sshd -t >/dev/null 2>&1 || { log::error "sshd configuration syntax test failed."; return 1; }; local p k pk r port; p="$(ssh::effective_value passwordauthentication)"; k="$(ssh::effective_value kbdinteractiveauthentication)"; pk="$(ssh::effective_value pubkeyauthentication)"; r="$(ssh::effective_value permitrootlogin)"; port="$(ssh::effective_value port)"; log::info "Effective SSH: port=$port PasswordAuthentication=$p KbdInteractiveAuthentication=$k PubkeyAuthentication=$pk PermitRootLogin=$r"; ssh::verify_effective_hardening && log::ok "Effective SSH hardening is active." || log::warn "Effective SSH hardening is incomplete."; ssh::has_valid_root_key && log::ok "At least one valid SSH public key is present for root." || log::warn "No valid SSH public keys found for root."; }
