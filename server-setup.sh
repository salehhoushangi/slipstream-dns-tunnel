#!/usr/bin/env bash
set -Eeuo pipefail

GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*" >&2; }
die()  { echo -e "${RED}[-]${NC} $*" >&2; exit 1; }

is_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && ((1 <= 10#$1 && 10#$1 <= 65535)); }

need_root_or_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi
  command -v sudo >/dev/null 2>&1 || die "Need root or sudo."
  sudo -n true >/dev/null 2>&1 || die "sudo needs a password; run: sudo -v first."
}

asroot() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

###############################################################################
# Inputs (keep them simple for SMS copy/paste)
###############################################################################
DOMAIN="${DOMAIN:-example.com}"                  # must match client
DNS_LISTEN_PORT="${DNS_LISTEN_PORT:-53}"         # usually 53
TARGET_ADDRESS="${TARGET_ADDRESS:-127.0.0.1:22}" # server-side service to forward to
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/src/slipstream-rust}"
REPO_HTTPS="${REPO_HTTPS:-https://github.com/Mygod/slipstream-rust.git}"
CARGO_PROFILE="${CARGO_PROFILE:-release}"        # release recommended
DISABLE_SYSTEMD_RESOLVED="${DISABLE_SYSTEMD_RESOLVED:-1}"
OPEN_FIREWALL="${OPEN_FIREWALL:-1}"

INSTALL_PARENT="$(dirname -- "$INSTALL_DIR")"

###############################################################################
# Validate
###############################################################################
is_port "$DNS_LISTEN_PORT" || die "Invalid DNS_LISTEN_PORT: $DNS_LISTEN_PORT"

log "Server setup starting..."
log "DOMAIN=$DOMAIN"
log "DNS_LISTEN_PORT=$DNS_LISTEN_PORT"
log "TARGET_ADDRESS=$TARGET_ADDRESS"
log "INSTALL_DIR=$INSTALL_DIR"
echo

need_root_or_sudo

###############################################################################
# Install deps + rustup
###############################################################################
log "Installing dependencies..."
asroot apt-get update -y
asroot apt-get install -y --no-install-recommends \
  git ca-certificates curl openssl build-essential cmake make pkg-config libssl-dev

if ! command -v rustup >/dev/null 2>&1; then
  log "Installing rustup..."
  curl -fsSL https://sh.rustup.rs | sh -s -- -y
fi

export PATH="$HOME/.cargo/bin:$PATH"
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
rustup default stable
command -v cargo >/dev/null 2>&1 || die "cargo not found after rustup install"

###############################################################################
# Clone + build
###############################################################################
log "Cloning/building slipstream..."
mkdir -p "$INSTALL_PARENT"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" pull --ff-only
else
  git clone "$REPO_HTTPS" "$INSTALL_DIR"
fi

git -C "$INSTALL_DIR" submodule update --init --recursive
cd "$INSTALL_DIR"

if [[ "$CARGO_PROFILE" == "release" ]]; then
  cargo build -p slipstream-server -p slipstream-client --release
else
  cargo build -p slipstream-server -p slipstream-client
fi

SERVER_BIN="$INSTALL_DIR/target/$CARGO_PROFILE/slipstream-server"
test -x "$SERVER_BIN" || die "Missing server binary: $SERVER_BIN"

###############################################################################
# Generate cert/key
###############################################################################
log "Generating cert/key (self-signed)..."
cd "$INSTALL_DIR"
if [[ ! -f cert.pem || ! -f key.pem ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout key.pem -out cert.pem -days 365 \
    -subj "/CN=${DOMAIN}"
fi
test -f cert.pem && test -f key.pem || die "cert/key not created"

###############################################################################
# Disable systemd-resolved if requested (frees port 53 on some servers)
###############################################################################
if [[ "$DISABLE_SYSTEMD_RESOLVED" == "1" ]]; then
  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    warn "Disabling systemd-resolved to free port ${DNS_LISTEN_PORT}..."
    asroot systemctl stop systemd-resolved || true
    asroot systemctl disable systemd-resolved || true
  else
    log "systemd-resolved not active, skipping."
  fi
else
  log "Skipping systemd-resolved disable (DISABLE_SYSTEMD_RESOLVED=0)."
fi

###############################################################################
# Open firewall UDP port
###############################################################################
if [[ "$OPEN_FIREWALL" == "1" ]]; then
  log "Opening firewall for UDP ${DNS_LISTEN_PORT} (best effort)..."

  if command -v ufw >/dev/null 2>&1; then
    asroot ufw allow "${DNS_LISTEN_PORT}/udp" || true
  fi

  if command -v iptables >/dev/null 2>&1; then
    if ! iptables -C INPUT -p udp --dport "$DNS_LISTEN_PORT" -j ACCEPT 2>/dev/null; then
      asroot iptables -A INPUT -p udp --dport "$DNS_LISTEN_PORT" -j ACCEPT
    fi
  fi
else
  log "Skipping firewall changes (OPEN_FIREWALL=0)."
fi

###############################################################################
# Systemd service
###############################################################################
log "Installing systemd service slipstream-server..."
SERVICE_FILE="/etc/systemd/system/slipstream-server.service"

asroot tee "$SERVICE_FILE" >/dev/null <<UNIT
[Unit]
Description=Slipstream Server (DNS tunnel)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$SERVER_BIN --dns-listen-port $DNS_LISTEN_PORT --target-address $TARGET_ADDRESS --domain $DOMAIN --cert $INSTALL_DIR/cert.pem --key $INSTALL_DIR/key.pem
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

asroot systemctl daemon-reload
asroot systemctl enable --now slipstream-server.service

log "Server is up."
log "Check: systemctl status slipstream-server"
log "Check UDP: ss -lunp | grep :${DNS_LISTEN_PORT}"
