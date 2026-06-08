{ config, pkgs, lib, ... }:
let
  jx-match = pkgs.buildGoModule {
    pname   = "jx-match";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner = "EugeneShtoka";
      repo  = "jx-match";
      rev   = "15424a70faa8fec49789e4dc83f1868f0da5ef1f";
      hash  = "sha256-xjc9uXYIQdYdE+JZrNWOq2xSRKkzq4T1VltjbASv+jg=";
    };
    vendorHash = "sha256-hzG7gFveP7vex+C52vsKqVguL3Quqtdh6HgSkT2dQaQ=";
  };

  clipkit = pkgs.buildGoModule {
    pname   = "clipkit";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner = "EugeneShtoka";
      repo  = "clipkit";
      rev   = "d533770d29eae21812f4508ebf164d7890fb36a2";
      hash  = "sha256-geMO+miqq7NHIXXIrxpC9Gxfm7v27P3F1AoGxqOe08s=";
    };
    vendorHash = null;
  };

  vortexd = pkgs.rustPlatform.buildRustPackage {
    pname   = "vortexd";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner  = "EugeneShtoka";
      repo   = "vortex";
      rev    = "cd259c34011d8afbb88c2d78b33bf633cf62007a";
      hash   = "sha256-YVJgJmF78xuc06hoqrknvWJSE0bzJAXN8Ck/1W0g0nY=";
    };
    cargoLock.lockFile = ./vortex-Cargo.lock;
    cargoBuildFlags    = [ "-p" "vortexd" ];
    doCheck            = false;
  };

  # check-space: exit 0 if room's parent space name is in MATRIX_CUSTOM_SPACES.
  # Uses the Matrix AS token (via MATRIX_ACCESS_TOKEN) with user impersonation.
  checkSpace = pkgs.writeShellScript "check-space" ''
    ROOM="$1"
    [ -z "$ROOM" ] && exit 1

    PARENTS=$(${pkgs.curl}/bin/curl -sf \
      -H "Authorization: Bearer $MATRIX_ACCESS_TOKEN" \
      "$MATRIX_SERVER/_matrix/client/v3/rooms/$ROOM/state?user_id=$MATRIX_USER_ID" \
      | ${pkgs.jq}/bin/jq -r '.[] | select(.type == "m.space.parent") | .state_key')

    [ -z "$PARENTS" ] && exit 1

    for SPACE_ID in $PARENTS; do
      NAME=$(${pkgs.curl}/bin/curl -sf \
        -H "Authorization: Bearer $MATRIX_ACCESS_TOKEN" \
        "$MATRIX_SERVER/_matrix/client/v3/rooms/$SPACE_ID/state/m.room.name?user_id=$MATRIX_USER_ID" \
        | ${pkgs.jq}/bin/jq -r '.name // empty')
      [ -z "$NAME" ] && continue
      if echo "$MATRIX_CUSTOM_SPACES" | ${pkgs.jq}/bin/jq -e --arg n "$NAME" \
          'any(.[]; . == $n)' >/dev/null 2>&1; then
        exit 0
      fi
    done
    exit 1
  '';

  # Non-secret environment for vortexd. MATRIX_ACCESS_TOKEN comes separately
  # from extractMatrixToken (derived from the mx-proxy sops secret at startup).
  matrixEnv = pkgs.writeText "matrix-env" ''
    MATRIX_SERVER=http://127.0.0.1:6167
    MATRIX_USER_ID=@eugene:matrix.cloud-surf.com
    MATRIX_CODE_SENDERS=[]
    MATRIX_CUSTOM_SPACES=["Friends","Social","Work","Colleagues"]
  '';

  vortexConfig = pkgs.writeText "vortex.toml" ''
    [server]
    unix_socket = "/run/vortex/vortex.sock"
    db_path     = "/var/lib/vortex/state.db"

    [workflows.mx-message]
    correlation_id = "{{trigger.id}}"

    [[workflows.mx-message.tasks]]
    type    = "notify"
    id      = "notify"
    topic   = "mx-notify"
    server  = "https://ntfy.cloud-surf.com"
    message = "{{trigger.text}}"
    title   = "{{trigger.sender}} [{{trigger.room}}]"
    when    = 'trigger.event_id == ""'

    [[workflows.mx-message.tasks]]
    type = "shell"
    id   = "check_space"
    exec = "${checkSpace} {{trigger.room}}"

    [[workflows.mx-message.tasks]]
    type    = "notify"
    id      = "notify_link"
    topic   = "mx-notify"
    server  = "https://ntfy.cloud-surf.com"
    message = "https://matrix.to/#/{{trigger.room}}/{{trigger.event_id}}"
    title   = "{{trigger.sender}} [{{trigger.room}}]"
    when    = "check_space"

    [[workflows.mx-message.tasks]]
    type = "spawn"
    id   = "check_code_sender"
    exe  = "jx-match"
    args = ["-e", "sender in env.MATRIX_CODE_SENDERS"]

    [[workflows.mx-message.tasks]]
    type = "spawn"
    id   = "extract_code"
    exe  = "clipkit"
    args = ["--json", "text", "--extract-code"]
    when = "check_code_sender && !check_space"

    [[workflows.mx-message.tasks]]
    type    = "notify"
    id      = "notify_clipboard"
    topic   = "mx-clipboard"
    server  = "https://ntfy.cloud-surf.com"
    message = "{{tasks.extract_code.stdout}}"
    when    = "extract_code"

    [[workflows.mx-message.tasks]]
    type     = "response"
    id       = "reply"
    template = '{"id":"{{correlation_id}}","status":"ok","text":{{json trigger.text}},"room_id":{{json trigger.room}},"sender":{{json trigger.sender}}}'
  '';

  # Extracts as_token from the decrypted mx-proxy sops secret and writes it
  # as MATRIX_ACCESS_TOKEN into the service state dir (mode 0400).
  extractMatrixToken = pkgs.writeShellScript "extract-matrix-token" ''
    TOKEN=$(${pkgs.gnugrep}/bin/grep 'as_token' ${config.sops.secrets.mx-proxy-config.path} \
      | ${pkgs.gnused}/bin/sed 's/.*= "\(.*\)"/\1/')
    printf 'MATRIX_ACCESS_TOKEN=%s\n' "$TOKEN" > /var/lib/vortex/matrix-token.env
    chown orchestrator:orchestrator /var/lib/vortex/matrix-token.env
    chmod 0400 /var/lib/vortex/matrix-token.env
  '';
in {
  users.groups.orchestrator = {};
  users.users.orchestrator = {
    isSystemUser = true;
    group        = "orchestrator";
  };

  systemd.services.vortexd = {
    description = "vortexd workflow daemon";
    after       = [ "network.target" ];
    wantedBy    = [ "multi-user.target" ];
    path        = [ jx-match clipkit ];
    serviceConfig = {
      User            = "orchestrator";
      Group           = "orchestrator";
      ExecStartPre    = "+${extractMatrixToken}";
      EnvironmentFile = [ "${matrixEnv}" "-/var/lib/vortex/matrix-token.env" ];
      ExecStart       = "${vortexd}/bin/vortexd ${vortexConfig}";
      RuntimeDirectory     = "vortex";
      RuntimeDirectoryMode = "0770";
      StateDirectory       = "vortex";
      UMask                = "0007";
      Restart              = "on-failure";
      RestartSec           = "5s";
      StandardOutput       = "journal";
      StandardError        = "journal";
      SyslogIdentifier     = "vortexd";
    };
  };
}
