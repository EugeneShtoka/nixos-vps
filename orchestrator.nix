{ config, pkgs, lib, ... }:
let
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
      rev    = "df83577853c4ffb05aa4fc53f52e4344f5392ffa";
      hash   = "sha256-PzyJZxY8KkgRboAandYWYZm4qvsEMl4X0m6iGpjgB5k=";
    };
    cargoLock.lockFile = ./vortex-Cargo.lock;
    cargoBuildFlags    = [ "-p" "vortexd" ];
    doCheck            = false;
  };

  # Non-secret environment for vortexd. MATRIX_ACCESS_TOKEN comes separately
  # from extractMatrixToken (derived from the mx-proxy sops secret at startup).
  matrixEnv = pkgs.writeText "matrix-env" ''
    MATRIX_SERVER=http://127.0.0.1:6167
    MATRIX_USER_ID=@eugene:matrix.cloud-surf.com
    MATRIX_CUSTOM_SPACES=["!YmVHgcBLpzR4fZ1fjJ:matrix.cloud-surf.com","!bSCdKJyP5D20sswOxD:matrix.cloud-surf.com","!w1kIQdLjYDUj7wgUis:matrix.cloud-surf.com","!UhvRHgZdEoHKMNgoud:matrix.cloud-surf.com"]
    # Friends=!YmVHgcBLpzR4fZ1fjJ Social=!bSCdKJyP5D20sswOxD Work=!w1kIQdLjYDUj7wgUis Colleagues=!UhvRHgZdEoHKMNgoud
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
    type    = "http"
    id      = "fetch_state"
    url     = "{{env.MATRIX_SERVER}}/_matrix/client/v3/rooms/{{trigger.room}}/state?user_id={{env.MATRIX_USER_ID}}"
    headers = { Authorization = "Bearer {{env.MATRIX_ACCESS_TOKEN}}" }

    [[workflows.mx-message.tasks]]
    type = "condition"
    id   = "in_custom_space"
    expr = 'tasks.fetch_state.success && tasks.fetch_state.output.exists(e, e.type == "m.space.parent" && e.state_key in env.MATRIX_CUSTOM_SPACES)'

    [[workflows.mx-message.tasks]]
    type    = "notify"
    id      = "notify_link"
    topic   = "mx-notify"
    server  = "https://ntfy.cloud-surf.com"
    message = "https://matrix.to/#/{{trigger.room}}/{{trigger.event_id}}"
    title   = "{{trigger.sender}} [{{trigger.room}}]"
    when    = "in_custom_space"

    [[workflows.mx-message.tasks]]
    type = "spawn"
    id   = "extract_code"
    exe  = "clipkit"
    args = ["--json", "text", "--extract-code"]
    when = "!in_custom_space"

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
    path        = [ clipkit ];
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
