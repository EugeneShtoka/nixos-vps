{ config, pkgs, lib, pkgs-unstable, ... }:
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
      rev    = "f4ff8e1abd2a47d438cf335814129506a560c1eb";
      hash   = "sha256-9F5v0hlhwEER6CgE+zQ+mpqolebL0JGQxPqeUvxLj1Q=";
    };
    vendorHash = "sha256-Upjt0Q2G6x5vGf0bG0TS9uWrHBow8/cQsZexhMgVb2I=";
  };

  whatsappPkg  = mkBridge "whatsapp"  "v0.2603.0" "sha256-1k3qcOL7arLiUOC4+EyBkZxvi0j12pdOE9kurA3Cbso=";
  gmessagesPkg = mkBridge "gmessages" "v0.2602.0" "sha256-6hU6FWwkEqvoi1yByBXWe0t6U9q7j8T/TM9ynuyeiGA=";
  metaPkg      = mkBridge "meta"      "v0.2602.0" "sha256-R6Pg1C2YhDhaJVxvaMZxluo3Si3Cgz3HP4HB9gWdU0w=";
  slackPkg     = mkBridge "slack"     "v0.2603.0" "sha256-DzV2uA/NEzrfgXahAjv8nyyI47jQnyle+wxmh59yp5w=";
  telegramPkg  = mkBridge "telegram"  "v0.2604.0" "sha256-MxEjaf43fdC++7zHntiN+eMdnRSIJB+sYpAIcTZAPK4=";
  signalPkg    = mkBridge "signal"    "v0.2604.0" "sha256-f0Nd5bcHxGngxdc/pVNGoL/HCZduIVJppPRVX0lIzkI=";
  linkedinPkg  = mkBridge "linkedin"  "v0.2602.0" "sha256-mvDchxkAA9/acDdo2EKDZx/pbTMC1r9CJVIOO27RwjA=";

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
in {
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
    extraGroups  = [ "vortex" ];
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
      ExecStart        = "${mx-proxy}/bin/mx-proxy --config /etc/mx-proxy/config.toml";
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
  systemd.services.mautrix-telegram    =
    mkBridgeService "mautrix-telegram"    telegramPkg  "mautrix-telegram";
  systemd.services.mautrix-signal      =
    mkBridgeService "mautrix-signal"      signalPkg    "mautrix-signal";
}
