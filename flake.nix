{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Pinned solely to ship vaultwarden >= 1.37.0 (client 2026.7.0+ dropped
    # compatibility with server 1.36.0). Isolated input = no blast radius.
    nixpkgs-vaultwarden.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { nixpkgs, nixpkgs-unstable, nixpkgs-vaultwarden, disko, sops-nix, ... }:
  let
    system = "x86_64-linux";
    pkgs-unstable = import nixpkgs-unstable { inherit system; };
    pkgs-vaultwarden = import nixpkgs-vaultwarden { inherit system; };
  in {
    nixosConfigurations.vps = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit pkgs-unstable pkgs-vaultwarden sops-nix; };
      modules = [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./disk-config.nix
        ./hardware-configuration.nix
        ./configuration.nix
      ];
    };
  };
}
