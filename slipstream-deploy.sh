#!/usr/bin/env bash
set -Eeuo pipefail

GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
STEP_NO=0

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*" >&2; }
die()  { echo -e "${RED}[-]${NC} $*" >&2; exit 1; }

step() {
  STEP_NO=$((STEP_NO+1))
  echo -e "\n${GREEN}== Step ${STEP_NO}: $* ==${NC}"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

is_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && ((1 <= 10#$1 && 10#$1 <= 65535)); }

prompt() {
  local var="$1" text="$2" def="${3:-}" val
  if [[ -n "${def}" ]]; then
    read -r -p "${text} [${def}]: " val
    val="${val:-$def}"
  else
    read -r -p "${text}: " val
    [[ -n "${val}" ]] || die "Value required: ${text}"
  fi
  val="$(trim "$val")"
  printf -v "$var" '%s' "$val"
}

prompt_allow_empty() {
  local var="$1" text="$2" def="${3:-}" val
  if [[ -n "${def}" ]]; then
    read -r -p "${text} [${def}]: " val
    val="${val:-$def}"
  else
    read -r -p "${text}: " val
  fi
  val="$(trim "$val")"
  printf -v "$var" '%s' "$val"
}

prompt_port() {
  local var="$1" text="$2" def="${3:-}" val
  while true; do
    if [[ -n "${def}" ]]; then
      read -r -p "${text} [${def}]: " val
      val="${val:-$def}"
    else
      read -r -p "${text}: " val
    fi
    val="$(trim "$val")"
    if is_port "$val"; then
      printf -v "$var" '%s' "$val"
      return 0
    fi
    warn "Invalid port: '$val' (must be 1..65535). Try again like a civilized carbon-based lifeform."
  done
}

prompt_yesno() {
  local var="$1" text="$2" def="${3:-y}" val
  read -r -p "${text} (y/n) [${def}]: " val
  val="$(trim "${val:-$def}")"
  case "$val" in
    y|Y) printf -v "$var" '1' ;;
    n|N) printf -v "$var" '0' ;;
    *) die "Please answer y or n." ;;
  esac
}

###############################################################################
# Defaults (override via env)
###############################################################################
SERVER_IP="${SERVER_IP:-}"
SERVER_USER="${SERVER_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-}"

DOMAIN="${DOMAIN:-example.com}"
DNS_LISTEN_PORT="${DNS_LISTEN_PORT:-53}"
CLIENT_TCP_PORT="${CLIENT_TCP_PORT:-7000}"
TARGET_ADDRESS="${TARGET_ADDRESS:-127.0.0.1:22}"

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/src/slipstream-rust}"
REPO_HTTPS="${REPO_HTTPS:-https://github.com/Mygod/slipstream-rust.git}"
CARGO_PROFILE="${CARGO_PROFILE:-release}"

DISABLE_SYSTEMD_RESOLVED="${DISABLE_SYSTEMD_RESOLVED:-1}"
OPEN_FIREWALL="${OPEN_FIREWALL:-1}"

INSTALL_PARENT=""

###############################################################################
# SSH ControlMaster
###############################################################################
SSH_CTRL_DIR="${SSH_CTRL_DIR:-/tmp/slipstream-ssh-ctrl}"
mkdir -p "${SSH_CTRL_DIR}"
chmod 700 "${SSH_CTRL_DIR}"
SSH_CTRL_SOCK="${SSH_CTRL_DIR}/cm-%r@%h:%p"

ssh_base_args=()

build_ssh_args() {
  ssh_base_args=(
    -p "${SSH_PORT}"
    -o StrictHostKeyChecking=accept-new
    -o BatchMode=no
    -o ControlMaster=auto
    -o ControlPersist=10m
    -o ControlPath="${SSH_CTRL_SOCK}"
    -o RequestTTY=no
  )
  if [[ -n "${SSH_KEY}" ]]; then
    ssh_base_args+=( -i "${SSH_KEY}" )
  fi
}

run_remote() {
  local desc="$1"
  step "${desc} (remote)"
  local ssh_cmd=( ssh "${ssh_base_args[@]}" )
  [[ "${SERVER_USER}" != "root" ]] && ssh_cmd+=( -tt )
  "${ssh_cmd[@]}" "${SERVER_USER}@${SERVER_IP}" "bash -s" || die "Remote step failed: ${desc}"
  log "OK: ${desc}"
}

run_remote_if_needed() {
  local desc="$1" check_script="$2" do_script="$3"
  step "${desc} (remote)"

  local ssh_cmd=( ssh "${ssh_base_args[@]}" )
  [[ "${SERVER_USER}" != "root" ]] && ssh_cmd+=( -tt )

  if printf "%s\n" "set -Eeuo pipefail" "${check_script}" \
    | "${ssh_cmd[@]}" "${SERVER_USER}@${SERVER_IP}" "bash -s" >/dev/null 2>&1; then
    log "SKIP: ${desc} (already OK)"
    return 0
  fi

  printf "%s\n" "set -Eeuo pipefail" "${do_script}" \
    | "${ssh_cmd[@]}" "${SERVER_USER}@${SERVER_IP}" "bash -s"

  log "OK: ${desc}"
}

run_local_if_needed() {
  local desc="$1" check_script="$2" do_script="$3"
  step "${desc}"

  if bash -s >/dev/null 2>&1 <<EOF
set -Eeuo pipefail
${check_script}
EOF
  then
    log "SKIP: ${desc} (already OK)"
    return 0
  fi

  bash -s <<EOF
set -Eeuo pipefail
${do_script}
EOF

  log "OK: ${desc}"
}

###############################################################################
# Inputs
###############################################################################
echo "Slipstream deployer (run on CLIENT)."
echo "It will setup SERVER+CLIENT and SKIP steps that are already correct."
echo

[[ -z "${SERVER_IP}" ]] && prompt SERVER_IP "Server public IP/hostname"
prompt SERVER_USER "Server SSH user" "${SERVER_USER}"
prompt_port SSH_PORT "Server SSH port" "${SSH_PORT}"
prompt_allow_empty SSH_KEY "Optional SSH key path (leave empty for password prompt)" "${SSH_KEY}"

prompt DOMAIN "Tunnel domain (must match both sides)" "${DOMAIN}"
prompt_port DNS_LISTEN_PORT "Server DNS listen port (53 recommended)" "${DNS_LISTEN_PORT}"
prompt_port CLIENT_TCP_PORT "Client local TCP listen port (you'll ssh to this locally)" "${CLIENT_TCP_PORT}"

prompt TARGET_ADDRESS "Server target-address (service on SERVER to forward to)" "${TARGET_ADDRESS}"
prompt INSTALL_DIR "Install dir on BOTH machines" "${INSTALL_DIR}"
INSTALL_PARENT="$(dirname -- "$INSTALL_DIR")"

prompt_yesno DISABLE_SYSTEMD_RESOLVED "Disable systemd-resolved on SERVER to free port ${DNS_LISTEN_PORT}?" \
  "$( [[ "${DISABLE_SYSTEMD_RESOLVED}" == "1" ]] && echo y || echo n )"
prompt_yesno OPEN_FIREWALL "Open SERVER firewall for UDP ${DNS_LISTEN_PORT} (ufw/iptables)?" \
  "$( [[ "${OPEN_FIREWALL}" == "1" ]] && echo y || echo n )"

build_ssh_args

echo
log "Plan:"
echo "  SERVER: ${SERVER_USER}@${SERVER_IP}:${SSH_PORT}"
echo "    - slipstream-server UDP:${DNS_LISTEN_PORT} -> ${TARGET_ADDRESS}"
echo "  CLIENT:"
echo "    - slipstream-client TCP:${CLIENT_TCP_PORT} -> resolver ${SERVER_IP}:${DNS_LISTEN_PORT}"
echo "  DOMAIN: ${DOMAIN}"
echo "  INSTALL_DIR: ${INSTALL_DIR}"
echo

###############################################################################
# Local preflight
###############################################################################
step "Check local prerequisites (ssh, curl, git)"
command -v ssh >/dev/null || die "ssh missing"
command -v curl >/dev/null || die "curl missing"
command -v git >/dev/null  || die "git missing"
log "OK: local prerequisites"

step "Open SSH control connection to server (may prompt password once)"
ssh -tt "${ssh_base_args[@]}" "${SERVER_USER}@${SERVER_IP}" "echo ok" >/dev/null
log "OK: Open SSH control connection"

###############################################################################
# Remote steps
###############################################################################
run_remote_if_needed \
  "SERVER: Install deps + rustup" \
  $'export PATH="$HOME/.cargo/bin:$PATH"\ncommand -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1 && command -v rustup >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1' \
  $'export DEBIAN_FRONTEND=noninteractive\nif [[ "$(id -u)" -eq 0 ]]; then\n  apt-get update -y\n  apt-get install -y --no-install-recommends git ca-certificates curl openssl build-essential cmake make pkg-config libssl-dev\nelse\n  sudo apt-get update -y\n  sudo apt-get install -y --no-install-recommends git ca-certificates curl openssl build-essential cmake make pkg-config libssl-dev\nfi\nif ! command -v rustup >/dev/null 2>&1; then\n  curl -fsSL https://sh.rustup.rs | sh -s -- -y\nfi\nexport PATH="$HOME/.cargo/bin:$PATH"\n[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"\nrustup default stable\ncommand -v cargo >/dev/null 2>&1'

run_remote_if_needed \
  "SERVER: Clone + build slipstream (server+client)" \
  $'test -x "'"${INSTALL_DIR}"'/target/'"${CARGO_PROFILE}"'/slipstream-server" && test -x "'"${INSTALL_DIR}"'/target/'"${CARGO_PROFILE}"'/slipstream-client"' \
  $'export PATH="$HOME/.cargo/bin:$PATH"\n[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"\ncommand -v cargo >/dev/null 2>&1 || { echo "cargo not found (PATH=$PATH)"; exit 1; }\nmkdir -p "'"${INSTALL_PARENT}"'"\nif [[ -d "'"${INSTALL_DIR}"'/.git" ]]; then\n  git -C "'"${INSTALL_DIR}"'" pull --ff-only\nelse\n  git clone "'"${REPO_HTTPS}"'" "'"${INSTALL_DIR}"'"\nfi\ngit -C "'"${INSTALL_DIR}"'" submodule update --init --recursive\ncd "'"${INSTALL_DIR}"'"\nif [[ "'"${CARGO_PROFILE}"'" == "release" ]]; then\n  cargo build -p slipstream-server -p slipstream-client --release\nelse\n  cargo build -p slipstream-server -p slipstream-client\nfi\ntest -x "'"${INSTALL_DIR}"'/target/'"${CARGO_PROFILE}"'/slipstream-server"\n.test -x "'"${INSTALL_DIR}"'/target/'"${CARGO_PROFILE}"'/slipstream-client"'

run_remote_if_needed \
  "SERVER: Generate cert/key" \
  $'test -f "'"${INSTALL_DIR}"'/cert.pem" && test -f "'"${INSTALL_DIR}"'/key.pem"' \
  $'cd "'"${INSTALL_DIR}"'"\nif [[ ! -f cert.pem || ! -f key.pem ]]; then\n  openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 365 -subj "/CN='"${DOMAIN}"'"\nfi\ntest -f cert.pem && test -f key.pem'

if [[ "${DISABLE_SYSTEMD_RESOLVED}" == "1" ]]; then
  run_remote_if_needed \
    "SERVER: Disable systemd-resolved" \
    $'systemctl is-active --quiet systemd-resolved && exit 1 || exit 0' \
    $'if [[ "$(id -u)" -eq 0 ]]; then\n  systemctl stop systemd-resolved || true\n  systemctl disable systemd-resolved || true\nelse\n  sudo systemctl stop systemd-resolved || true\n  sudo systemctl disable systemd-resolved || true\nfi'
else
  step "SERVER: (Optional) Disable systemd-resolved"
  log "SKIP: user chose not to disable"
fi

if [[ "${OPEN_FIREWALL}" == "1" ]]; then
  run_remote "SERVER: Open firewall UDP port" <<EOF
set -Eeuo pipefail
p="${DNS_LISTEN_PORT}"

asroot() {
  if [[ "\$(id -u)" -eq 0 ]]; then
    "\$@"
  else
    sudo "\$@"
  fi
}

if command -v ufw >/dev/null 2>&1; then
  if ! ufw status 2>/dev/null | grep -Fq "\${p}/udp"; then
    asroot ufw allow "\${p}/udp" || true
  fi
fi

if command -v iptables >/dev/null 2>&1; then
  if ! iptables -C INPUT -p udp --dport "\${p}" -j ACCEPT 2>/dev/null; then
    asroot iptables -A INPUT -p udp --dport "\${p}" -j ACCEPT
  fi
fi
EOF
else
  step "SERVER: (Optional) Open firewall UDP port"
  log "SKIP: user chose not to open firewall"
fi

run_remote_if_needed \
  "SERVER: Create + start systemd service" \
  $'systemctl is-active --quiet slipstream-server.service' \
  $'BIN="'"${INSTALL_DIR}"'/target/'"${CARGO_PROFILE}"'/slipstream-server"\n[[ -x "$BIN" ]] || { echo "Missing server binary: $BIN"; exit 1; }\nif [[ "$(id -u)" -eq 0 ]]; then\n  tee /etc/systemd/system/slipstream-server.service >/dev/null <<'"'"'UNIT'"'"'\n[Unit]\nDescription=Slipstream Server (DNS tunnel)\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=__EXECSTART__\nRestart=on-failure\nRestartSec=2\n\n[Install]\nWantedBy=multi-user.target\nUNIT\n  sed -i "s|^ExecStart=__EXECSTART__|ExecStart=$BIN --dns-listen-port '"${DNS_LISTEN_PORT}"' --target-address '"${TARGET_ADDRESS}"' --domain '"${DOMAIN}"' --cert '"${INSTALL_DIR}"'/cert.pem --key '"${INSTALL_DIR}"'/key.pem|" /etc/systemd/system/slipstream-server.service\n  systemctl daemon-reload\n  systemctl enable --now slipstream-server.service\nelse\n  sudo tee /etc/systemd/system/slipstream-server.service >/dev/null <<'"'"'UNIT'"'"'\n[Unit]\nDescription=Slipstream Server (DNS tunnel)\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=__EXECSTART__\nRestart=on-failure\nRestartSec=2\n\n[Install]\nWantedBy=multi-user.target\nUNIT\n  sudo sed -i "s|^ExecStart=__EXECSTART__|ExecStart=$BIN --dns-listen-port '"${DNS_LISTEN_PORT}"' --target-address '"${TARGET_ADDRESS}"' --domain '"${DOMAIN}"' --cert '"${INSTALL_DIR}"'/cert.pem --key '"${INSTALL_DIR}"'/key.pem|" /etc/systemd/system/slipstream-server.service\n  sudo systemctl daemon-reload\n  sudo systemctl enable --now slipstream-server.service\nfi\nsystemctl is-active --quiet slipstream-server.service'

###############################################################################
# Client steps
###############################################################################
run_local_if_needed \
  "CLIENT: Acquire sudo (needed for apt/systemd)" \
  $'sudo -n true >/dev/null 2>&1' \
  $'sudo true'

run_local_if_needed \
  "CLIENT: Install deps + rustup" \
  $'command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1 && command -v rustup >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1' \
  $'export DEBIAN_FRONTEND=noninteractive\nsudo apt-get update -y\nsudo apt-get install -y --no-install-recommends git ca-certificates curl openssl build-essential cmake make pkg-config libssl-dev\nif ! command -v rustup >/dev/null 2>&1; then\n  curl -fsSL https://sh.rustup.rs | sh -s -- -y\nfi\nexport PATH="$HOME/.cargo/bin:$PATH"\n[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"\nrustup default stable\ncommand -v cargo >/dev/null 2>&1'

run_local_if_needed \
  "CLIENT: Clone + build slipstream-client" \
  $'test -x "'"${INSTALL_DIR}"'/target/'"${CARGO_PROFILE}"'/slipstream-client"' \
  $'export PATH="$HOME/.cargo/bin:$PATH"\n[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"\nmkdir -p "'"${INSTALL_PARENT}"'"\nif [[ -d "'"${INSTALL_DIR}"'/.git" ]]; then\n  git -C "'"${INSTALL_DIR}"'" pull --ff-only\nelse\n  git clone "'"${REPO_HTTPS}"'" "'"${INSTALL_DIR}"'"\nfi\ngit -C "'"${INSTALL_DIR}"'" submodule update --init --recursive\ncd "'"${INSTALL_DIR}"'"\nif [[ "'"${CARGO_PROFILE}"'" == "release" ]]; then\n  cargo build -p slipstream-client --release\nelse\n  cargo build -p slipstream-client\nfi\ntest -x "'"${INSTALL_DIR}"'/target/'"${CARGO_PROFILE}"'/slipstream-client"'

run_local_if_needed \
  "CLIENT: Create + start systemd service for slipstream-client" \
  $'systemctl is-active --quiet slipstream-client.service' \
  $'BIN="'"${INSTALL_DIR}"'/target/'"${CARGO_PROFILE}"'/slipstream-client"\n[[ -x "$BIN" ]] || die "Missing client binary: $BIN"\nif ! command -v systemctl >/dev/null 2>&1; then\n  die "systemctl not found on CLIENT (no systemd). Run client manually: $BIN --tcp-listen-port '"${CLIENT_TCP_PORT}"' --resolver '"${SERVER_IP}"':'"${DNS_LISTEN_PORT}"' --domain '"${DOMAIN}"'"\nfi\nsudo tee /etc/systemd/system/slipstream-client.service >/dev/null <<'"'"'UNIT'"'"'\n[Unit]\nDescription=Slipstream Client (DNS tunnel)\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=__EXECSTART__\nRestart=on-failure\nRestartSec=2\n\n[Install]\nWantedBy=multi-user.target\nUNIT\nsudo sed -i "s|^ExecStart=__EXECSTART__|ExecStart=$BIN --tcp-listen-port '"${CLIENT_TCP_PORT}"' --resolver '"${SERVER_IP}"':'"${DNS_LISTEN_PORT}"' --domain '"${DOMAIN}"'|" /etc/systemd/system/slipstream-client.service\nsudo systemctl daemon-reload\nsudo systemctl enable --now slipstream-client.service\nsudo systemctl is-active --quiet slipstream-client.service'

step "Final usage"
echo "Client tunnel is listening on: 127.0.0.1:${CLIENT_TCP_PORT}"
echo "If your server target is SSH (${TARGET_ADDRESS}), connect from CLIENT like:"
echo "  ssh -p ${CLIENT_TCP_PORT} user@127.0.0.1"
log "Deployment finished successfully."
