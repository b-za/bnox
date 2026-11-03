{
  description = "bnox — unified NixOS base";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      agenix,
      disko,
      ...
    }:
    let
      system = "x86_64-linux";

      hostsDir = ./hosts;
      hostEntries =
        if builtins.pathExists hostsDir then
          builtins.readDir hostsDir
        else
          { };
      hostNames = builtins.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory") hostEntries
      );
    in
    {
      nixosModules.bnox = {
        imports = [
          home-manager.nixosModules.home-manager
          agenix.nixosModules.default
          disko.nixosModules.disko
          ./modules/default.nix
        ];
      };

      nixosModules.bnox-base = {
        imports = [
          home-manager.nixosModules.home-manager
          ./modules/base/default.nix
        ];
      };

      nixosConfigurations = builtins.listToAttrs (
        map (name: {
          inherit name;
          value = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = {
              bnox = self;
            };
            modules = [
              self.nixosModules.bnox
              ./hosts/${name}/configuration.nix
            ];
          };
        }) hostNames
      );

      profiles = {
        minimal = ./modules/profiles/minimal.nix;
        server = ./modules/profiles/server.nix;
        desktop = ./modules/profiles/desktop.nix;
      };

      hardware = { };

      lib = import ./lib/default.nix { lib = nixpkgs.lib; };

      packages.${system} = { };
    };
}
