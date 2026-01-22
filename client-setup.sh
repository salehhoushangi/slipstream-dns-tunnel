#!/usr/bin/env bash
set -Eeuo pipefail

GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*" >&2; }
die()  { echo -e "${RED}[-]${NC} $*" >&2; exit 1; }

is_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && ((1 <= 10#$1 && 10#$1 <= 65535)); }

SERVER_IP="${SERVER_IP:-}"                       # REQUIRED
DOMAIN="${DOMAIN:-example.com}"                  # must match server
DNS_LISTEN_PORT="${DNS_LISTEN_PORT:-53}"         # must match server
CLIENT_TCP_PORT="${CLIENT_TCP_PORT:-7000}"       # local port to ssh into

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/src/slipstream-rust}"
REPO_HTTPS="${REPO_HTTPS:-https://github.com/Mygod/slipstream-rust.git}"
CARGO_PROFILE="${CARGO_PROFILE:-release}"

INSTALL_PARENT="$(dirname -- "$INSTALL_DIR")"

[[ -n "$SERVER_IP" ]] || die "SERVER_IP is required. Example: SERVER_IP=1.2.3.4 ./client-setup.sh"
is_port "$DNS_LISTEN_PORT" || die "Invalid DNS_LISTEN_PORT: $DNS_LISTEN_PORT"
is_port "$CLIENT_TCP_PORT" || die "Invalid CLIENT_TCP_PORT: $CLIENT_TCP_PORT"

log "Client setup starting..."
log "SERVER_IP=$SERVER_IP"
log "DOMAIN=$DOMAIN"
log "DNS_LISTEN_PORT=$DNS_LISTEN_PORT"
log "CLIENT_TCP_PORT=$CLIENT_TCP_PORT"
echo

command -v sudo >/dev/null 2>&1 || die "sudo required"

log "Installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  git ca-certificates curl openssl build-essential cmake make pkg-config libssl-dev

if ! command -v rustup >/dev/null 2>&1; then
  log "Installing rustup..."
  curl -fsSL https://sh.rustup.rs | sh -s -- -y
fi

export PATH="$HOME/.cargo/bin:$PATH"
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
rustup default stable
command -v cargo >/dev/null 2>&1 || die "cargo not found after rustup install"

log "Cloning/building slipstream-client..."
mkdir -p "$INSTALL_PARENT"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" pull --ff-only
else
  git clone "$REPO_HTTPS" "$INSTALL_DIR"
fi

git -C "$INSTALL_DIR" submodule update --init --recursive
cd "$INSTALL_DIR"

if [[ "$CARGO_PROFILE" == "release" ]]; then
  cargo build -p slipstream-client --release
else
  cargo build -p slipstream-client
fi

CLIENT_BIN="$INSTALL_DIR/target/$CARGO_PROFILE/slipstream-client"
test -x "$CLIENT_BIN" || die "Missing client binary: $CLIENT_BIN"

log "Installing systemd service slipstream-client..."
SERVICE_FILE="/etc/systemd/system/slipstream-client.service"

sudo tee "$SERVICE_FILE" >/dev/null <<UNIT
[Unit]
Description=Slipstream Client (DNS tunnel)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$CLIENT_BIN --tcp-listen-port $CLIENT_TCP_PORT --resolver $SERVER_IP:$DNS_LISTEN_PORT --domain $DOMAIN
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now slipstream-client.service

log "Client is up."
log "Now connect:"
echo "  ssh -p ${CLIENT_TCP_PORT} root@127.0.0.1"
log "Check: systemctl status slipstream-client"
