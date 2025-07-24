# installer/installer-module.nix
# NixOS module that embeds our automated installer into the live system

{ config, modulesPath, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.vybovaly-installer;
  runtimeInputs = with pkgs; [
    # Core system tools
    coreutils
    util-linux
    procps

    # Network tools
    curl
    openssh

    # Disk management
    e2fsprogs
    dosfstools
    mdadm
    disko

    # NixOS tools
    nixos-install-tools
    git
    nix
  ];
in
{
  options.services.vybovaly-installer = {
    enable = mkEnableOption "Automated NixOS installer";
  };

  # Base system configuration for netboot using official NixOS netboot module
  imports = [
    (modulesPath + "/installer/netboot/netboot.nix")
  ];

  config = mkIf cfg.enable {
    # Install our library functions
    environment.etc."vybovaly-installer-lib.sh" = {
      source = ./vybovaly-installer-lib.sh;
      mode = "0444";
    };

    system.build.vybovaly-installer = pkgs.writeShellApplication {
      inherit runtimeInputs;

      name = "vybovaly-installer";
      text = ''
        source ${./vybovaly-installer-lib.sh}
        if should_run_automation "$@"; then
          run_installer
        fi
      '';
    };

    # Use modern kernel
    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;

    # Network configuration for installer
    networking = {
      hostName = lib.mkDefault "vybovaly";
      useNetworkd = lib.mkDefault true;
      wireless.enable = lib.mkDefault false;
    };
    systemd.network.enable = lib.mkDefault true;

    # SSH for debugging
    services.openssh = {
      enable = lib.mkDefault true;
      settings = {
        PermitRootLogin = lib.mkDefault "yes";
        PasswordAuthentication = lib.mkDefault false;
        PubkeyAuthentication = lib.mkDefault true;
      };
    };

    # Add version information
    environment.etc."vybovaly-info" = {
      text = ''
        Vybovaly Installer
        Built: dev-build
        System: ${config.system.nixos.version}
      '';
      mode = "0444";
    };

    # Ensure required directories exist
    systemd.tmpfiles.rules = [
      "d /tmp/vybovaly-installer 0755 root root -"
      "d /var/log/vybovaly-installer 0755 root root -"
    ];

    # Custom udev rules for better disk detection
    services.udev.extraRules = ''
      # Ensure all disks are available before starting installation
      SUBSYSTEM=="block", KERNEL=="sd[a-z]", ACTION=="add", RUN+="${pkgs.coreutils}/bin/sleep 2"
    '';

    # Systemd service for automation
    systemd.services.vybovaly-installer = {
      description = "NixOS Automated Installation Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };

      environment = {
        NIX_PATH = "nixpkgs=${pkgs.path}";
      };

      path = runtimeInputs;

      script = ''
        set -euo pipefail

        source /etc/vybovaly-installer-lib.sh

        if should_run_automation; then
          echo "Starting Vybovaly automated NixOS installation"
          run_automated_installation
        else
          echo "No automation parameters detected, skipping Vybovaly automated NixOS installation"
        fi
      '';
    };
  };
}
