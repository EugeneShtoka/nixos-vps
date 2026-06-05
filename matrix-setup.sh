#!/bin/bash
# Run as root on the VPS after nixos-rebuild to configure the Matrix stack.
# Usage: bash matrix-setup.sh
set -euo pipefail

DOMAIN="matrix.cloud-surf.com"
EUGENE="@eugene:${DOMAIN}"
REG_TOKEN="$(head -c 24 /dev/urandom | base64 | tr -d '/')"
DOUBLEPUPPET_TOKEN="YOUR_DOUBLEPUPPET_TOKEN"

echo "=== Matrix stack setup ==="
echo "Domain: ${DOMAIN}"
echo "Registration token: ${REG_TOKEN}"
echo

# ---------------------------------------------------------------------------
# Write tuwunel.toml skeleton (appservices appended below)
# ---------------------------------------------------------------------------
cat > /etc/tuwunel/tuwunel.toml <<EOF
[global]
  server_name = "${DOMAIN}"
  database_path = "/var/lib/tuwunel"
  address = ["127.0.0.1"]
  port = 6167
  allow_registration = true
  registration_token = "${REG_TOKEN}"
  allow_local_presence = true
  log = "warn,tuwunel=info"

EOF
chmod 640 /etc/tuwunel/tuwunel.toml
chown tuwunel:tuwunel /etc/tuwunel/tuwunel.toml

# ---------------------------------------------------------------------------
# Per-bridge setup
# ---------------------------------------------------------------------------
setup_bridge() {
    local svc="$1"      # mautrix-whatsapp-bg
    local binary="$2"   # mautrix-whatsapp
    local port="$3"
    local bot="$4"      # whatsappbot_bg
    local bridge_id="$5"  # whatsapp-bg
    local user_tmpl="$6"  # whatsapp_bg_{{.}}

    local cfg="/etc/${svc}/config.yaml"
    local reg="/etc/${svc}/registration.yaml"
    local lib="/var/lib/${svc}"

    echo "--- ${svc} ---"

    # Seed config with just enough for -g to succeed
    cat > "${cfg}" <<SEEDEOF
homeserver:
    address: http://localhost:6167
    domain: ${DOMAIN}
    software: standard
appservice:
    address: http://localhost:${port}
    hostname: 127.0.0.1
    port: ${port}
    id: ${bridge_id}
    bot:
        username: ${bot}
        displayname: Bridge Bot
    username_template: "${user_tmpl}"
database:
    type: sqlite3-fk-wal
    uri: ${lib}/bridge.db
SEEDEOF
    chown matrix:matrix "${cfg}"

    # Generate registration with fresh tokens
    sudo -u matrix "${binary}" -g -c "${cfg}" -r "${reg}"
    chmod 640 "${reg}"
    chown matrix:matrix "${reg}"

    # Extract tokens from registration.yaml
    local as_token hs_token sender
    as_token=$(grep '^as_token:' "${reg}" | awk '{print $2}')
    hs_token=$(grep '^hs_token:' "${reg}" | awk '{print $2}')
    sender=$(grep '^sender_localpart:' "${reg}" | awk '{print $2}')

    if [[ -z "${as_token}" || -z "${hs_token}" ]]; then
        echo "ERROR: failed to extract tokens from ${reg}" >&2
        cat "${reg}" >&2
        exit 1
    fi

    # Write the final, complete config
    cat > "${cfg}" <<CFGEOF
homeserver:
    address: http://localhost:8900
    domain: ${DOMAIN}
    software: standard

appservice:
    address: http://localhost:${port}
    hostname: 127.0.0.1
    port: ${port}
    id: ${bridge_id}
    bot:
        username: ${bot}
        displayname: Bridge Bot
    as_token: "${as_token}"
    hs_token: "${hs_token}"
    username_template: "${user_tmpl}"
    ephemeral_events: true

database:
    type: sqlite3-fk-wal
    uri: ${lib}/bridge.db

bridge:
    permissions:
        "${EUGENE}": admin
CFGEOF
    chown matrix:matrix "${cfg}"
    chmod 640 "${cfg}"

    echo "  as_token: ${as_token:0:8}..."
    echo "  hs_token: ${hs_token:0:8}..."

    # Append appservice block to tuwunel.toml
    # Escape dot in domain for regex
    local dom_escaped="${DOMAIN//./\\\\.}"
    local bot_regex="^@${bot}:${dom_escaped}$"

    # User regex: based on username_template prefix before {{.}}
    local tmpl_prefix="${user_tmpl%%_\{\{.\}\}}"
    local user_regex="^@${tmpl_prefix}_.*:${dom_escaped}$"

    cat >> /etc/tuwunel/tuwunel.toml <<TOMLEOF
[global.appservice.${bridge_id}]
url = "http://localhost:8901"
as_token = "${as_token}"
hs_token = "${hs_token}"
sender_localpart = "${sender}"
rate_limited = false
receive_ephemeral = true

[[global.appservice.${bridge_id}.users]]
exclusive = true
regex = "${bot_regex}"

[[global.appservice.${bridge_id}.users]]
exclusive = true
regex = "${user_regex}"

TOMLEOF

    echo "  Registered in tuwunel.toml"
}

# ---------------------------------------------------------------------------
# Bridges
# ---------------------------------------------------------------------------
setup_bridge mautrix-whatsapp-bg mautrix-whatsapp 29318 whatsappbot_bg whatsapp-bg "whatsapp_bg_{{.}}"
setup_bridge mautrix-whatsapp-il mautrix-whatsapp 29319 whatsappbot_il whatsapp-il "whatsapp_il_{{.}}"
setup_bridge mautrix-slack       mautrix-slack    29320 slackbot       slack       "slack_{{.}}"
setup_bridge mautrix-meta        mautrix-meta     29321 metabot        meta        "meta_{{.}}"
setup_bridge mautrix-linkedin    mautrix-linkedin 29322 linkedinbot    linkedin    "linkedin_{{.}}"
setup_bridge mautrix-telegram    mautrix-telegram 29323 telegrambot    telegram    "telegram_{{.}}"
setup_bridge mautrix-signal      mautrix-signal   29328 signalbot      signal      "signal_{{.}}"
setup_bridge mautrix-gmessages   mautrix-gmessages 29336 gmessagesbot  gmessages   "gmessages_{{.}}"

# ---------------------------------------------------------------------------
# Write vortex config
# ---------------------------------------------------------------------------
cat > /etc/vortex/vortex.toml <<'VORTEXEOF'
[server]
unix_socket = "/run/vortex/vortex.sock"
db_path     = "/var/lib/vortex/state.db"
VORTEXEOF
chmod 640 /etc/vortex/vortex.toml
chown vortex:vortex /etc/vortex/vortex.toml

# ---------------------------------------------------------------------------
# Write mx-proxy config (hs_tokens extracted from registrations above)
# ---------------------------------------------------------------------------
cat > /etc/mx-proxy/config.toml <<MXEOF
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

MXEOF

declare -A BRIDGE_PORTS=(
  [whatsapp-bg]=29318  [whatsapp-il]=29319  [slack]=29320
  [meta]=29321         [linkedin]=29322     [telegram]=29323
  [signal]=29328       [gmessages]=29336
)
for bridge_id in "${!BRIDGE_PORTS[@]}"; do
    svc="mautrix-${bridge_id}"
    reg="/etc/${svc}/registration.yaml"
    port="${BRIDGE_PORTS[$bridge_id]}"
    hs_token=$(grep '^hs_token:' "${reg}" | awk '{print $2}')
    cat >> /etc/mx-proxy/config.toml <<BRIDGEOF

[[bridges]]
name     = "${bridge_id}"
url      = "http://127.0.0.1:${port}"
hs_token = "${hs_token}"
BRIDGEOF
done

chmod 640 /etc/mx-proxy/config.toml
chown matrix:matrix /etc/mx-proxy/config.toml

# ---------------------------------------------------------------------------
# Start services
# ---------------------------------------------------------------------------
echo
echo "=== Starting services ==="

systemctl restart tuwunel
echo "Waiting for tuwunel to be ready..."
for i in $(seq 1 20); do
    if curl -sf http://localhost:6167/_matrix/client/versions > /dev/null 2>&1; then
        echo "tuwunel is ready"
        break
    fi
    sleep 1
done

systemctl daemon-reload
systemctl restart vortexd
echo "Waiting for vortex socket..."
for i in $(seq 1 15); do
    [[ -S /run/vortex/vortex.sock ]] && break
    sleep 1
done

systemctl restart mx-proxy
echo "Started mx-proxy"

# Start all bridges
for svc in mautrix-whatsapp-bg mautrix-whatsapp-il mautrix-slack mautrix-meta \
           mautrix-linkedin mautrix-telegram mautrix-signal mautrix-gmessages; do
    systemctl reset-failed "${svc}" 2>/dev/null || true
    systemctl restart "${svc}"
    echo "Started ${svc}"
done

echo
echo "=== Setup complete ==="
echo
echo "Registration token for new accounts: ${REG_TOKEN}"
echo "Next: create your user account in Element with the token above."
echo "Then DM each bridge bot to log in:"
echo "  @whatsappbot_bg:${DOMAIN}   — WhatsApp BG (+359884650326)"
echo "  @whatsappbot_il:${DOMAIN}   — WhatsApp IL (+972545347450)"
echo "  @slackbot:${DOMAIN}         — Slack"
echo "  @metabot:${DOMAIN}          — Facebook/Instagram"
echo "  @linkedinbot:${DOMAIN}      — LinkedIn"
echo "  @telegrambot:${DOMAIN}      — Telegram"
echo "  @signalbot:${DOMAIN}        — Signal"
echo "  @gmessagesbot:${DOMAIN}     — Google Messages"
echo
echo "Check service logs with: journalctl -u tuwunel -f"
