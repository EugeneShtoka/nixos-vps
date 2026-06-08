#!/bin/bash
# One-time migration: wire existing bridges through mx-proxy + vortexd.
# Run as root on the VPS after nixos-rebuild has installed the new binaries.
# Safe to re-run — all writes are idempotent.
set -euo pipefail

DOMAIN="matrix.cloud-surf.com"
DOUBLEPUPPET_TOKEN="taIRrQgnSPPLXILg76ZA1G6SWVB9hRzYWocD6gh5KM"

echo "=== Matrix proxy migration ==="

# ---------------------------------------------------------------------------
# 1. Write vortex config (minimal — no workflows, acts as pass-through)
# ---------------------------------------------------------------------------
echo "--- Writing /etc/vortex/vortex.toml ---"
cat > /etc/vortex/vortex.toml <<'EOF'
[server]
unix_socket = "/run/vortex/vortex.sock"
db_path     = "/var/lib/vortex/state.db"
EOF
chmod 640 /etc/vortex/vortex.toml
chown vortex:vortex /etc/vortex/vortex.toml

# ---------------------------------------------------------------------------
# 2. Build mx-proxy config from existing bridge registration.yaml files
# ---------------------------------------------------------------------------
echo "--- Building /etc/mx-proxy/config.toml ---"

# Bridge name → port mapping
declare -A BRIDGE_PORTS=(
  [whatsapp-bg]=29318
  [whatsapp-il]=29319
  [slack]=29320
  [meta]=29321
  [linkedin]=29322
  [telegram]=29323
  [signal]=29328
  [gmessages]=29336
)

cat > /etc/mx-proxy/config.toml <<EOF
[upstream]
homeserver = "http://127.0.0.1:6167"
as_token   = "${DOUBLEPUPPET_TOKEN}"

[listen]
cs = "127.0.0.1:8900"
as = "127.0.0.1:8901"

[processor]
transport        = "unix"
endpoint         = "/run/vortex/vortex.sock"
send_template    = '{"workflow":"mx-message","params":{"text":"{{.Body}}","room":"{{.RoomID}}","sender":"{{.Sender}}"}}'
[processor.receive_mapping]
body        = "output.text"
destination = "output.destination"

EOF

for bridge_id in "${!BRIDGE_PORTS[@]}"; do
    svc="mautrix-${bridge_id}"
    reg="/etc/${svc}/registration.yaml"
    port="${BRIDGE_PORTS[$bridge_id]}"

    if [[ ! -f "$reg" ]]; then
        echo "  WARN: $reg not found — skipping $bridge_id"
        continue
    fi

    hs_token=$(grep '^hs_token:' "$reg" | awk '{print $2}')
    if [[ -z "$hs_token" ]]; then
        echo "  WARN: no hs_token in $reg — skipping $bridge_id"
        continue
    fi

    cat >> /etc/mx-proxy/config.toml <<EOF
[[bridges]]
name     = "${bridge_id}"
url      = "http://127.0.0.1:${port}"
hs_token = "${hs_token}"

EOF
    echo "  Added bridge: ${bridge_id} (port ${port})"
done

chmod 640 /etc/mx-proxy/config.toml
chown matrix:matrix /etc/mx-proxy/config.toml

# ---------------------------------------------------------------------------
# 3. Update bridge configs: homeserver.address → mx-proxy CS port
# ---------------------------------------------------------------------------
echo "--- Updating bridge homeserver.address to :8900 ---"
for svc in mautrix-whatsapp-bg mautrix-whatsapp-il mautrix-slack mautrix-meta \
           mautrix-linkedin mautrix-telegram mautrix-signal mautrix-gmessages; do
    cfg="/etc/${svc}/config.yaml"
    if [[ -f "$cfg" ]]; then
        sed -i 's|address: http://localhost:6167|address: http://localhost:8900|g' "$cfg"
        sed -i 's|address: http://127.0.0.1:6167|address: http://127.0.0.1:8900|g' "$cfg"
        echo "  Updated $cfg"
    fi
done

# ---------------------------------------------------------------------------
# 4. Update tuwunel.toml: appservice urls → mx-proxy AS port
# ---------------------------------------------------------------------------
echo "--- Updating tuwunel.toml appservice urls to :8901 ---"
# Matches any bridge port (29318, 29319, 29320, 29321, 29322, 29323, 29328, 29336)
sed -i 's|url = "http://localhost:293[0-9][0-9]"|url = "http://localhost:8901"|g' \
    /etc/tuwunel/tuwunel.toml
# gmessages uses port 29336 — same pattern, but let's be explicit
sed -i 's|url = "http://localhost:29336"|url = "http://localhost:8901"|g' \
    /etc/tuwunel/tuwunel.toml

# ---------------------------------------------------------------------------
# 5. Restart services in dependency order
# ---------------------------------------------------------------------------
echo "--- Restarting services ---"

systemctl restart tuwunel
echo "  tuwunel restarted"

# Start vortexd (new service — systemd may not know about it yet after rebuild)
systemctl daemon-reload
systemctl restart vortexd
echo "  vortexd started"

# Wait for vortex socket
for i in $(seq 1 15); do
    if [[ -S /run/vortex/vortex.sock ]]; then
        echo "  vortex socket ready"
        break
    fi
    sleep 1
done

systemctl restart mx-proxy
echo "  mx-proxy started"

# Restart all bridges
for svc in mautrix-whatsapp-bg mautrix-whatsapp-il mautrix-slack mautrix-meta \
           mautrix-linkedin mautrix-telegram mautrix-signal mautrix-gmessages; do
    systemctl reset-failed "${svc}" 2>/dev/null || true
    systemctl restart "${svc}"
    echo "  ${svc} restarted"
done

echo
echo "=== Migration complete ==="
echo "Check logs: journalctl -u mx-proxy -u vortexd -f"
echo "Check status: systemctl status mx-proxy vortexd mautrix-whatsapp-bg"
