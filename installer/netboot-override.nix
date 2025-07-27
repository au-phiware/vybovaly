# Wrapper around the standard NixOS netboot module that prefixes the official
# ipxe script

modulesPath:

args@{ config, lib, pkgs, ... }:

let
  # Import the original netboot module to get its configuration
  originalNetboot = import (modulesPath + "/installer/netboot/netboot.nix") args;
in
{
  # Import everything from the original module except the conflicting system.build entries
  imports = originalNetboot.imports or [ ];
  options = originalNetboot.options or { };

  # Apply the original config but override specific system.build outputs
  config = lib.mkMerge [
    # Original config without the system.build parts we want to change
    (lib.removeAttrs (originalNetboot.config or { }) [ "system" ])

    # Our custom system.build configuration
    {
      system.build = lib.mkMerge [
        # Include original system.build except the ones we override
        (lib.removeAttrs (originalNetboot.config.system.build or { }) [ "netbootIpxeScript" ])

        # Our overrides
        {
          # Create an iPXE script that merges our prefix with NixOS netboot script
          netbootIpxeScript = pkgs.writeTextDir "netboot.ipxe" (builtins.concatStringsSep "\n" [
            (builtins.readFile ./netboot-prefix.ipxe)
            (builtins.readFile "${originalNetboot.config.system.build.netbootIpxeScript}/netboot.ipxe")
          ]);
        }
      ];
    }
  ];
}
