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
      rev    = "437597ccc2b5a47b78a2e12118b7f9f7d5115605";
      hash   = "sha256-oL6DZIPzKA10y3zWh1TYxJvOdaTibxXTdMIe0EjhNuE=";
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
    bind        = "0.0.0.0:9001"
    auth_method = "env"
    auth_key    = "VORTEX_TOKEN"

    [workflows.mx-message]
    correlation_id = "{{trigger.id}}"

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "is_spam"
    depends_on = []
    expr       = 'trigger.room in env.MATRIX_SPAMMERS'

    [[workflows.mx-message.tasks]]
    type       = "response"
    id         = "reply"
    depends_on = ["is_spam"]
    template   = '{"id":"{{correlation_id}}","status":"{{#if tasks.is_spam.success}}drop{{else}}ok{{/if}}","text":{{json trigger.text}},"room_id":{{json trigger.room}},"sender":{{json trigger.sender}}}'
    abort_if   = "is_spam"

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "matched_space"
    depends_on = ["reply"]
    expr       = 'trigger.room in globals.space_map ? globals.space_map[trigger.room] : ""'

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "resolved_sender"
    depends_on = ["reply"]
    expr       = 'trigger.sender != "" ? trigger.sender : env.MATRIX_USER_ID'

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "room_name_cached"
    depends_on = ["reply"]
    expr       = '"room_names" in globals && trigger.room in globals.room_names ? globals.room_names[trigger.room] : ""'

    [[workflows.mx-message.tasks]]
    type       = "http"
    id         = "fetch_room_name"
    depends_on = ["room_name_cached"]
    when       = "NOT room_name_cached"
    url        = "{{env.MATRIX_SERVER}}/_matrix/client/v3/rooms/{{trigger.room}}/state/m.room.name?user_id={{env.MATRIX_USER_ID}}"
    headers    = { Authorization = "Bearer {{env.MATRIX_ACCESS_TOKEN}}" }

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "new_room_names"
    depends_on = ["fetch_room_name"]
    when       = "fetch_room_name"
    expr       = 'merge("room_names" in globals ? globals.room_names : {}, toMap([{"id": trigger.room}], "id", tasks.fetch_room_name.output.name))'

    [[workflows.mx-message.tasks]]
    type       = "store_set"
    id         = "cache_room_name"
    depends_on = ["new_room_names"]
    when       = "new_room_names"
    set        = { room_names = "{{tasks.new_room_names.stdout}}" }

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "room_name"
    depends_on = ["room_name_cached", "fetch_room_name"]
    expr       = 'tasks.room_name_cached.stdout != "" ? tasks.room_name_cached.stdout : (tasks.fetch_room_name.success ? tasks.fetch_room_name.output.name : trigger.room)'

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "sender_name_cached"
    depends_on = ["resolved_sender"]
    expr       = '"user_names" in globals && tasks.resolved_sender.stdout in globals.user_names ? globals.user_names[tasks.resolved_sender.stdout] : ""'

    [[workflows.mx-message.tasks]]
    type       = "http"
    id         = "fetch_sender_name"
    depends_on = ["sender_name_cached"]
    when       = "NOT sender_name_cached"
    url        = "{{env.MATRIX_SERVER}}/_matrix/client/v3/profile/{{tasks.resolved_sender.stdout}}/displayname?user_id={{env.MATRIX_USER_ID}}"
    headers    = { Authorization = "Bearer {{env.MATRIX_ACCESS_TOKEN}}" }

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "new_user_names"
    depends_on = ["fetch_sender_name"]
    when       = "fetch_sender_name"
    expr       = 'merge("user_names" in globals ? globals.user_names : {}, toMap([{"id": tasks.resolved_sender.stdout}], "id", tasks.fetch_sender_name.output.displayname))'

    [[workflows.mx-message.tasks]]
    type       = "store_set"
    id         = "cache_sender_name"
    depends_on = ["new_user_names"]
    when       = "new_user_names"
    set        = { user_names = "{{tasks.new_user_names.stdout}}" }

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "sender_name"
    depends_on = ["sender_name_cached", "fetch_sender_name"]
    expr       = 'tasks.sender_name_cached.stdout != "" ? tasks.sender_name_cached.stdout : (tasks.fetch_sender_name.success ? tasks.fetch_sender_name.output.displayname : tasks.resolved_sender.stdout)'

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "sender_display"
    depends_on = ["sender_name"]
    expr       = 'regex_replace(tasks.sender_name.stdout, " \\([^)]*\\)$", "")'

    [[workflows.mx-message.tasks]]
    type       = "eval"
    id         = "title"
    depends_on = ["sender_display", "room_name"]
    expr       = 'tasks.sender_display.stdout == tasks.room_name.stdout ? tasks.sender_display.stdout : tasks.sender_display.stdout + " [" + tasks.room_name.stdout + "]"'

    [[workflows.mx-message.tasks]]
    type       = "http"
    id         = "notify"
    depends_on = ["matched_space", "title"]
    when       = 'trigger.event_id == ""'
    url        = "https://ntfy.cloud-surf.com/mx-notify{{#if tasks.matched_space.stdout}}-{{tasks.matched_space.stdout}}{{/if}}"
    method     = "POST"
    body       = "{{trigger.text}}"
    headers    = { Title = "{{tasks.title.stdout}}" }

    [[workflows.mx-message.tasks]]
    type       = "spawn"
    id         = "extract_url"
    depends_on = ["matched_space"]
    exe        = "clipkit"
    args       = ["--json", "text", "--extract-url"]
    when       = 'matched_space && trigger.event_id == ""'

    [[workflows.mx-message.tasks]]
    type       = "spawn"
    id         = "extract_code"
    depends_on = ["matched_space", "extract_url"]
    exe        = "clipkit"
    args       = ["--json", "text", "--extract-code"]
    when       = '!matched_space && trigger.event_id == ""'

    [[workflows.mx-message.tasks]]
    type       = "http"
    id         = "notify_clipboard"
    depends_on = ["extract_url", "extract_code"]
    url        = "https://ntfy.cloud-surf.com/mx-clipboard"
    method     = "POST"
    body       = "{{tasks.extract_url.stdout}}{{tasks.extract_code.stdout}}"
    when       = "extract_url || extract_code"


    [workflows.space-map]
    cron = "0 * * * *"

    [[workflows.space-map.tasks]]
    type       = "foreach"
    id         = "build_map"
    items      = "env.MATRIX_SPACES"
    initial    = "{}"
    accumulate = "merge(toMap(tasks.fetch.output.filter(e, e.type == 'm.space.child'), 'state_key', item.name), acc)"
    tasks      = [{ id = "fetch", type = "http", url = "{{env.MATRIX_SERVER}}/_matrix/client/v3/rooms/{{item.id}}/state?user_id={{env.MATRIX_USER_ID}}", headers = { Authorization = "Bearer {{env.MATRIX_ACCESS_TOKEN}}" } }]

    [[workflows.space-map.tasks]]
    type       = "store_set"
    id         = "save_map"
    depends_on = ["build_map"]
    set        = { space_map = "{{tasks.build_map.stdout}}" }
  '';

  # Extracts as_token from the decrypted mx-proxy sops secret and writes it
  # as MATRIX_ACCESS_TOKEN into the service state dir (mode 0400).
  waitTailscaleIp = pkgs.writeShellScript "wait-tailscale-ip" ''
    for i in $(seq 1 30); do
      ${pkgs.iproute2}/bin/ip addr show dev tailscale0 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -q 'inet ' && exit 0
      sleep 1
    done
    echo "tailscale0 has no inet address after 30s" >&2
    exit 1
  '';

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
    after       = [ "network.target" "tailscaled.service" ];
    wantedBy    = [ "multi-user.target" ];
    path        = [ clipkit ];
    serviceConfig = {
      User            = "orchestrator";
      Group           = "orchestrator";
      ExecStartPre    = [ "${waitTailscaleIp}" "+${extractMatrixToken}" ];
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
