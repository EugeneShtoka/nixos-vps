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
      rev    = "31c7bdef7c606b29753029b9e7ae7bde63c22f88";
      hash   = "sha256-XLXrkKYfxvmKLDOomLHJiAjNqPC6FX1DDcfSU9bE6vk=";
    };
    cargoLock.lockFile = ./vortex-Cargo.lock;
    cargoBuildFlags    = [ "-p" "vortexd" ];
    doCheck            = false;
  };

  # Each entry: name used for task IDs / ntfy topic suffix,
  # envKey for the env var name, id is the Matrix room ID.
  spaces = [
    { name = "friends";    envKey = "FRIENDS";    id = "!YmVHgcBLpzR4fZ1fjJ:matrix.cloud-surf.com"; }
    { name = "social";     envKey = "SOCIAL";     id = "!bSCdKJyP5D20sswOxD:matrix.cloud-surf.com"; }
    { name = "work";       envKey = "WORK";       id = "!w1kIQdLjYDUj7wgUis:matrix.cloud-surf.com"; }
    { name = "colleagues"; envKey = "COLLEAGUES"; id = "!UhvRHgZdEoHKMNgoud:matrix.cloud-surf.com"; }
  ];

  mkSpaceEnvLine = { envKey, id, ... }: "MATRIX_SPACE_${envKey}=${id}\n";

  mkSpaceTasks = { name, envKey, ... }: ''

    [[workflows.mx-message.tasks]]
    type       = "condition"
    id         = "in_${name}"
    depends_on = ["fetch_state"]
    expr       = 'tasks.fetch_state.success && tasks.fetch_state.output.exists(e, e.type == "m.space.parent" && e.state_key == env.MATRIX_SPACE_${envKey})'

    [[workflows.mx-message.tasks]]
    type       = "http"
    id         = "notify_${name}"
    depends_on = ["in_${name}"]
    url        = "https://ntfy.cloud-surf.com/mx-notify-${name}"
    method     = "POST"
    body       = "https://matrix.to/#/{{trigger.room}}/{{trigger.event_id}}"
    when       = "in_${name}"
    headers    = { Title = "{{trigger.sender}} [{{trigger.room}}]" }
  '';

  spaceEnvLines  = lib.concatMapStrings mkSpaceEnvLine spaces;
  spaceTasksToml = lib.concatMapStrings mkSpaceTasks spaces;

  # "in_friends", "in_social", ... — used in depends_on arrays
  spaceCondIds   = lib.concatStringsSep ", " (map (s: ''"in_${s.name}"'') spaces);
  # "notify_friends", ... — used in reply depends_on
  spaceNotifyIds = lib.concatStringsSep ", " (map (s: ''"notify_${s.name}"'') spaces);
  # !(in_friends || in_social || ...) — used in clipboard when conditions
  notInAnySpace  = "!(" + lib.concatStringsSep " || " (map (s: "in_${s.name}") spaces) + ")";

  # Non-secret environment for vortexd. MATRIX_ACCESS_TOKEN comes separately
  # from extractMatrixToken (derived from the mx-proxy sops secret at startup).
  matrixEnv = pkgs.writeText "matrix-env" ''
    MATRIX_SERVER=http://127.0.0.1:6167
    MATRIX_USER_ID=@eugene:matrix.cloud-surf.com
    ${spaceEnvLines}
  '';

  vortexConfig = pkgs.writeText "vortex.toml" ''
    [server]
    unix_socket = "/run/vortex/vortex.sock"
    db_path     = "/var/lib/vortex/state.db"

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
    headers    = { Authorization = "Bearer {{env.MATRIX_ACCESS_TOKEN}}" }
    ${spaceTasksToml}

    [[workflows.mx-message.tasks]]
    type       = "spawn"
    id         = "extract_url"
    depends_on = [${spaceCondIds}]
    exe        = "clipkit"
    args       = ["--json", "text", "--extract-url"]
    when       = '${notInAnySpace} && trigger.event_id != ""'

    [[workflows.mx-message.tasks]]
    type       = "spawn"
    id         = "extract_code"
    depends_on = [${spaceCondIds}, "extract_url"]
    exe        = "clipkit"
    args       = ["--json", "text", "--extract-code"]
    when       = '${notInAnySpace} && trigger.event_id != "" && !extract_url'

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
    depends_on = ["notify", ${spaceNotifyIds}, "notify_clipboard"]
    template   = '{"id":"{{correlation_id}}","status":"ok","text":{{json trigger.text}},"room_id":{{json trigger.room}},"sender":{{json trigger.sender}}}'
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
