{ config, pkgs, lib, ... }:
let
  mkBridge = name: version: hash:
    pkgs.stdenv.mkDerivation {
      pname    = "mautrix-${name}";
      inherit version;
      src = pkgs.fetchurl {
        url = "https://github.com/mautrix/${name}/releases/download/${version}/mautrix-${name}-amd64";
        inherit hash;
      };
      nativeBuildInputs = [ pkgs.autoPatchelfHook ];
      buildInputs        = [ pkgs.stdenv.cc.cc.lib ];
      dontUnpack         = true;
      dontBuild          = true;
      installPhase       = "install -Dm755 $src $out/bin/mautrix-${name}";
    };

  tuwunel = pkgs.stdenv.mkDerivation {
    pname   = "tuwunel";
    version = "1.5.1";
    src = pkgs.fetchurl {
      url  = "https://github.com/matrix-construct/tuwunel/releases/download/v1.5.1/v1.5.1-release-all-x86_64-v1-linux-gnu-tuwunel.zst";
      hash = "sha256-2j+EqWC+vnGgQtOz6UlrLfTAvubQyUjGG5Wq0/5VdwI=";
    };
    nativeBuildInputs = [ pkgs.zstd pkgs.autoPatchelfHook ];
    buildInputs        = [ pkgs.stdenv.cc.cc.lib ];
    dontBuild          = true;
    unpackPhase        = "zstd -d $src -o tuwunel";
    installPhase       = "install -Dm755 tuwunel $out/bin/tuwunel";
  };

  mx-proxy = pkgs.buildGoModule {
    pname   = "mx-proxy";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner  = "EugeneShtoka";
      repo   = "mx-proxy";
      rev    = "ec965719f0cc7b53933591272d7ce611bfb91ca1";
      hash   = "sha256-GhUGvdnE2HdWS95xxHLYRj6Ia2vp9C83QhOLyc5IWR4=";
    };
    vendorHash = "sha256-Upjt0Q2G6x5vGf0bG0TS9uWrHBow8/cQsZexhMgVb2I=";
  };

  whatsappPkg  = mkBridge "whatsapp"  "v0.2605.0" "sha256-xceFfF9jfD0UUvW0gFIOnV6RiEbKoO7GhqCrIozU9K8=";
  gmessagesPkg = mkBridge "gmessages" "v0.2605.0" "sha256-7jE/rdcUqtCVgPtvgTP+Tghmo5QQfm3MMYCR9sLjfY0=";
  metaPkg      = mkBridge "meta"      "v0.2605.1" "sha256-FSYxOjSu1I4tUTZWEomH5c1/igq0obQnT7Cc6q+n6zg=";
  slackPkg     = mkBridge "slack"     "v0.2605.0" "sha256-kOMD0zm2mW9a0sUwWXTA1Mli4Mhk6MDm6pzCGFA3v2s=";
  telegramPkg  = mkBridge "telegram"  "v0.2605.0" "sha256-EeAL95VncTaKdutzWpqe5XzyfIvgD+chka/qxwsmlDc=";
  signalPkg    = mkBridge "signal"    "v0.2605.0" "sha256-cIfPkNxNAtW/debwL6Jg+YO+MK6Q+2it3pdKK9ycOg4=";
  linkedinPkg  = mkBridge "linkedin"  "v0.2604.0" "sha256-yyreX/QaOsOc7fcQcz8y9u2q7/FO+4Xihi6gI04GAYs=";

  mkBridgeService = svcName: binPkg: binName: {
    description = "Matrix ${svcName} bridge";
    after       = [ "network.target" "mx-proxy.service" ];
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      User             = "matrix";
      Group            = "matrix";
      ExecStart        = "${binPkg}/bin/${binName} --config /etc/${svcName}/config.yaml";
      WorkingDirectory = "/var/lib/${svcName}";
      Restart          = "on-failure";
      RestartSec       = "5s";
      StandardOutput   = "journal";
      StandardError    = "journal";
      SyslogIdentifier = svcName;
    };
  };

  spaces = [
    { name = "friends";    id = "!YmVHgcBLpzR4fZ1fjJ:matrix.cloud-surf.com"; }
    { name = "work";       id = "!w1kIQdLjYDUj7wgUis:matrix.cloud-surf.com"; }
    { name = "social";     id = "!bSCdKJyP5D20sswOxD:matrix.cloud-surf.com"; }
    { name = "colleagues"; id = "!UhvRHgZdEoHKMNgoud:matrix.cloud-surf.com"; }
  ];

  spacesJson = "[" + lib.concatStringsSep "," (map (s: ''{\"id\":\"${s.id}\",\"name\":\"${s.name}\"}'') spaces) + "]";

  matrixEnv = pkgs.writeText "matrix-env" ''
    MATRIX_SERVER=http://127.0.0.1:6167
    MATRIX_USER_ID=@eugene:matrix.cloud-surf.com
    MATRIX_SPACES=${spacesJson}
  '';
in {
  options.matrix.envFile = lib.mkOption {
    type     = lib.types.package;
    readOnly = true;
    internal = true;
  };
  config = {
  matrix.envFile = matrixEnv;

  users.groups.tuwunel = {};
  users.groups.matrix  = {};
  users.users.tuwunel = {
    isSystemUser = true;
    group        = "tuwunel";
    home         = "/var/lib/tuwunel";
    createHome   = false;
  };
  users.users.matrix = {
    isSystemUser = true;
    group        = "matrix";
    extraGroups  = [ "orchestrator" ];
    home         = "/var/lib/matrix";
    createHome   = false;
  };

  systemd.tmpfiles.rules = [
    "d /etc/tuwunel                  0750 tuwunel tuwunel - -"
    "d /var/lib/tuwunel              0750 tuwunel tuwunel - -"
    "d /etc/mx-proxy                 0750 matrix  matrix  - -"
    "d /etc/mautrix-whatsapp-bg      0750 matrix  matrix  - -"
    "d /var/lib/mautrix-whatsapp-bg  0750 matrix  matrix  - -"
    "d /etc/mautrix-whatsapp-il      0750 matrix  matrix  - -"
    "d /var/lib/mautrix-whatsapp-il  0750 matrix  matrix  - -"
    "d /etc/mautrix-gmessages        0750 matrix  matrix  - -"
    "d /var/lib/mautrix-gmessages    0750 matrix  matrix  - -"
    "d /etc/mautrix-meta             0750 matrix  matrix  - -"
    "d /var/lib/mautrix-meta         0750 matrix  matrix  - -"
    "d /etc/mautrix-linkedin         0750 matrix  matrix  - -"
    "d /var/lib/mautrix-linkedin     0750 matrix  matrix  - -"
    "d /etc/mautrix-slack            0750 matrix  matrix  - -"
    "d /var/lib/mautrix-slack        0750 matrix  matrix  - -"
    "d /etc/mautrix-telegram         0750 matrix  matrix  - -"
    "d /var/lib/mautrix-telegram     0750 matrix  matrix  - -"
    "d /etc/mautrix-signal           0750 matrix  matrix  - -"
    "d /var/lib/mautrix-signal       0750 matrix  matrix  - -"
  ];

  environment.systemPackages = [
    tuwunel
    whatsappPkg
    gmessagesPkg
    metaPkg
    slackPkg
    telegramPkg
    signalPkg
    linkedinPkg
  ];

  systemd.services.tuwunel = {
    description = "Tuwunel Matrix homeserver";
    after       = [ "network.target" ];
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      User             = "tuwunel";
      Group            = "tuwunel";
      ExecStart        = "${tuwunel}/bin/tuwunel --config /etc/tuwunel/tuwunel.toml";
      WorkingDirectory = "/var/lib/tuwunel";
      Restart          = "on-failure";
      RestartSec       = "5s";
      StandardOutput   = "journal";
      StandardError    = "journal";
      SyslogIdentifier = "tuwunel";
    };
  };

  systemd.services.mx-proxy = {
    description = "mx-proxy Matrix event proxy";
    after       = [ "network.target" "tuwunel.service" "vortexd.service" ];
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      User             = "matrix";
      Group            = "matrix";
      ExecStart        = "${mx-proxy}/bin/mx-proxy --config /run/secrets/mx-proxy-config";
      Restart          = "on-failure";
      RestartSec       = "5s";
      StandardOutput   = "journal";
      StandardError    = "journal";
      SyslogIdentifier = "mx-proxy";
    };
  };

  systemd.services.mautrix-whatsapp-bg =
    mkBridgeService "mautrix-whatsapp-bg" whatsappPkg  "mautrix-whatsapp";
  systemd.services.mautrix-whatsapp-il =
    mkBridgeService "mautrix-whatsapp-il" whatsappPkg  "mautrix-whatsapp";
  systemd.services.mautrix-gmessages   =
    mkBridgeService "mautrix-gmessages"   gmessagesPkg "mautrix-gmessages";
  systemd.services.mautrix-meta        =
    mkBridgeService "mautrix-meta"        metaPkg      "mautrix-meta";
  systemd.services.mautrix-linkedin    =
    mkBridgeService "mautrix-linkedin"    linkedinPkg  "mautrix-linkedin";
  systemd.services.mautrix-slack       =
    mkBridgeService "mautrix-slack"       slackPkg     "mautrix-slack";
  systemd.services.mautrix-signal      =
    mkBridgeService "mautrix-signal"      signalPkg    "mautrix-signal";

  # Telegram needs api_id + api_hash injected from sops before each start
  systemd.services.mautrix-telegram = lib.mkMerge [
    (mkBridgeService "mautrix-telegram" telegramPkg "mautrix-telegram")
    {
      serviceConfig.ExecStartPre = pkgs.writeShellScript "patch-telegram-api" ''
        sed -i "s/api_id: .*/api_id: $(cat ${config.sops.secrets.telegram-api-id.path})/" /etc/mautrix-telegram/config.yaml
        sed -i "s/api_hash: .*/api_hash: $(cat ${config.sops.secrets.telegram-api-hash.path})/" /etc/mautrix-telegram/config.yaml
      '';
    }
  ];
  };
}
