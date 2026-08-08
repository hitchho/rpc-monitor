#!/usr/bin/env bash
set -euo pipefail

BIN="${BIN:-target/release/rpc-monitor}"
REMOTE_BIN="${REMOTE_BIN:-/usr/local/bin/rpc-monitor}"
SSH_USER="${SSH_USER:-root}"
CONFIRM_PRODUCTION_DEPLOY="${CONFIRM_PRODUCTION_DEPLOY:-}"
# DEPLOY_CONFIG=yes also ships the updated monitor.toml (adds the HTTP
# transport entries) and the systemd units, then restarts the monitor.
DEPLOY_CONFIG="${DEPLOY_CONFIG:-}"
APP_DIR="${APP_DIR:-/opt/rpc-monitor}"
HOSTS=(
  "mon-us-east.rpc-providers.net"
  "mon-eu-central.rpc-providers.net"
  "mon-ap-southeast.rpc-providers.net"
  # Rotko Networks monitor node (fork deployment; must be reachable by SSH
  # from the network this script runs on - the host resets connections from
  # non-allowlisted IPs).
  "monitor.rotko.net"
)

if [[ "$CONFIRM_PRODUCTION_DEPLOY" != "yes" ]]; then
  echo "Refusing production deploy: explicit user confirmation is required." >&2
  echo "After confirmation, run with: CONFIRM_PRODUCTION_DEPLOY=yes ./deploy.sh" >&2
  exit 2
fi

if [[ ! -x "$BIN" ]]; then
  echo "Missing executable binary: $BIN" >&2
  echo "Build it first with: cargo build --release" >&2
  exit 1
fi

for host in "${HOSTS[@]}"; do
  target="${SSH_USER}@${host}"
  tmp="/tmp/rpc-monitor.$$.new"

  echo "Deploying $BIN to ${target}:${REMOTE_BIN}"
  scp "$BIN" "${target}:${tmp}"
  ssh "$target" "install -m 0755 '$tmp' '$REMOTE_BIN' && rm -f '$tmp' && '$REMOTE_BIN' --help >/dev/null"

  if [[ "$DEPLOY_CONFIG" == "yes" ]]; then
    echo "Deploying config + units to ${target}:${APP_DIR}"
    ssh "$target" "mkdir -p '$APP_DIR'"
    scp "monitor.toml" "${target}:${APP_DIR}/monitor.toml.new"
    scp deploy/rpc-monitor.service deploy/rpc-monitor.timer "${target}:/tmp/"
    ssh "$target" \
      "set -e; install -m 0644 '$APP_DIR/monitor.toml.new' '$APP_DIR/monitor.toml' && rm -f '$APP_DIR/monitor.toml.new';" \
      "install -m 0644 /tmp/rpc-monitor.service /etc/systemd/system/rpc-monitor.service; install -m 0644 /tmp/rpc-monitor.timer /etc/systemd/system/rpc-monitor.timer; rm -f /tmp/rpc-monitor.service /tmp/rpc-monitor.timer;" \
      "systemctl daemon-reload; systemctl restart rpc-monitor.service 2>/dev/null || true; systemctl enable --now rpc-monitor.timer 2>/dev/null || true; systemctl start rpc-monitor.timer 2>/dev/null || true"
  fi
done

echo "Deploy complete."
