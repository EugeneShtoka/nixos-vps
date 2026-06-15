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
      rev    = "b0216b6bc9c68e08cc7d848d4009409fe0f173bc";
      hash   = "sha256-9DtdhMX5C+7WF/6rLktyUKaXcGZBWs4xD1LnhJYE/Go=";
    };
    cargoLock.lockFile = ./vortex-Cargo.lock;
    cargoBuildFlags    = [ "-p" "vortexd" ];
    doCheck            = false;
  };

  vortexConfig = pkgs.writeText "vortex.toml" ''
    [server]
    unix_socket = "/run/vortex/vortex.sock"
    db_path     = "/var/lib/vortex/state.db"

    [server.network]
    enabled     = true
    bind        = "100.64.0.1:9001"
    auth_method = "env"
    auth_key    = "VORTEX_TOKEN"

    [workflows.mx-message]
    correlation_id = "{{trigger.id}}"

    [[workflows.mx-message.tasks]]
    type       = "http"
    id         = "notify"
    depends_on = []
    url        = "https://ntfy.cloud-surf.com/mx-notify"
    method     = "POST"
    body       = "{{trigger.text}}"
    when       = 'trigger.event_id == ""'
    headers    = { Title = "{{trigger.sender}} [{{trigger.room}}]" }

    [[workflows.mx-message.tasks]]
    type       = "http"
    id         = "fetch_state"
    depends_on = []
    url        = "{{env.MATRIX_SERVER}}/_matrix/client/v3/rooms/{{trigger.room}}/state?user_id={{env.MATRIX_USER_ID}}"
    when       = 'trigger.event_id != ""'
    headers    = { Authorization = "Bearer {{env.MATRIX_ACCESS_TOKEN}}" }

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "matched_space"
    depends_on = ["fetch_state"]
    when       = 'trigger.event_id != ""'
    expr       = 'env.MATRIX_SPACES.filter(s, tasks.fetch_state.output.exists(e, e.type == "m.space.parent" && e.state_key == s.id)).map(s, s.name)[0]'

    [[workflows.mx-message.tasks]]
    type       = "http"
    id         = "notify_space"
    depends_on = ["matched_space"]
    when       = "matched_space"
    url        = "https://ntfy.cloud-surf.com/mx-notify-{{tasks.matched_space.stdout}}"
    method     = "POST"
    body       = "https://matrix.to/#/{{trigger.room}}/{{trigger.event_id}}"
    headers    = { Title = "{{trigger.sender}} [{{trigger.room}}]" }

    [[workflows.mx-message.tasks]]
    type       = "spawn"
    id         = "extract_url"
    depends_on = ["matched_space"]
    exe        = "clipkit"
    args       = ["--json", "text", "--extract-url"]
    when       = 'matched_space && trigger.event_id != ""'

    [[workflows.mx-message.tasks]]
    type       = "spawn"
    id         = "extract_code"
    depends_on = ["matched_space", "extract_url"]
    exe        = "clipkit"
    args       = ["--json", "text", "--extract-code"]
    when       = '!matched_space && trigger.event_id != ""'

    [[workflows.mx-message.tasks]]
    type       = "http"
    id         = "notify_clipboard"
    depends_on = ["extract_url", "extract_code"]
    url        = "https://ntfy.cloud-surf.com/mx-clipboard"
    method     = "POST"
    body       = "{{tasks.extract_url.stdout}}{{tasks.extract_code.stdout}}"
    when       = "extract_url || extract_code"

    [[workflows.mx-message.tasks]]
    type       = "response"
    id         = "reply"
    depends_on = []
    template   = '{"id":"{{correlation_id}}","status":"ok","text":{{json trigger.text}},"room_id":{{json trigger.room}},"sender":{{json trigger.sender}}}'
  '';

  # Extracts as_token from the decrypted mx-proxy sops secret and writes it
  # as MATRIX_ACCESS_TOKEN into the service state dir (mode 0400).
  extractMatrixToken = pkgs.writeShellScript "extract-matrix-token" ''
    TOKEN=$(${pkgs.gnugrep}/bin/grep 'as_token' ${config.sops.secrets.mx-proxy-config.path} \
      | ${pkgs.gnused}/bin/sed 's/.*= "\(.*\)"/\1/')
    printf 'MATRIX_ACCESS_TOKEN=%s\n' "$TOKEN"                           >  /var/lib/vortex/matrix-token.env
    printf 'VORTEX_TOKEN=%s\n' "$(cat ${config.sops.secrets.vortex-token.path})" >> /var/lib/vortex/matrix-token.env
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
      EnvironmentFile = [ "${config.matrix.envFile}" "-/var/lib/vortex/matrix-token.env" ];
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
