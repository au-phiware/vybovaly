{
  description = "Minimal NixOS configuration for vybovaly installer testing";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      generic = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./generic.nix ];
      };
      qemu-guest = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./qemu-guest.nix ];
      };
    };
  };
}
