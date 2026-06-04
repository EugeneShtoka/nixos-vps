{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { nixpkgs, nixpkgs-unstable, disko, sops-nix, ... }:
  let
    system = "x86_64-linux";
    pkgs-unstable = import nixpkgs-unstable { inherit system; };
  in {
    nixosConfigurations.vps = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit pkgs-unstable sops-nix; };
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
