# modules/gpu.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.gpu-server;
in
{
  options.services.gpu-server = {
    enable = mkEnableOption "GPU server configuration";

    nvidia = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable NVIDIA GPU support";
      };

      package = mkOption {
        type = types.package;
        default = config.boot.kernelPackages.nvidiaPackages.stable;
        description = "NVIDIA driver package";
      };

      datacenterDriver = mkOption {
        type = types.bool;
        default = false;
        description = "Use datacenter drivers for enterprise GPUs";
      };
    };

    cuda = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable CUDA support";
      };
    };

    docker = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Docker with GPU support";
      };
    };

    monitoring = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable GPU monitoring";
      };
    };
  };

  config = mkIf cfg.enable {
    # NVIDIA Configuration
    services.xserver.videoDrivers = mkIf cfg.nvidia.enable [ "nvidia" ];

    hardware.nvidia = mkIf cfg.nvidia.enable {
      modesetting.enable = true;
      powerManagement.enable = false;
      powerManagement.finegrained = false;
      open = false;
      nvidiaSettings = true;
      package = cfg.nvidia.package;

      # Data center driver configuration
      datacenter = mkIf cfg.nvidia.datacenterDriver {
        enable = true;
        settings = {
          # Disable graphics features for compute-only workloads
          "NoLogo" = "1";
          "UseDisplayDevice" = "none";
        };
      };
    };

    # CUDA Support
    nixpkgs.config.allowUnfree = true;

    environment.systemPackages = with pkgs; mkMerge [
      # Base GPU tools
      [
        nvidia-smi
        nvtop
        glxinfo
      ]

      # CUDA packages
      (mkIf cfg.cuda.enable [
        cudatoolkit
        cudnn
        nccl
        tensorrt
      ])

      # Development tools
      [
        gcc
        cmake
        pkg-config
      ]
    ];

    # Docker with GPU support
    virtualisation.docker = mkIf cfg.docker.enable {
      enable = true;
      enableNvidia = cfg.nvidia.enable;
      daemon.settings = {
        default-runtime = "nvidia";
        runtimes.nvidia = {
          path = "${pkgs.nvidia-docker}/bin/nvidia-container-runtime";
        };
      };
    };

    # NVIDIA Container Toolkit
    hardware.nvidia-container-toolkit.enable = mkIf (cfg.nvidia.enable && cfg.docker.enable) true;

    # GPU Monitoring
    services.prometheus.exporters.nvidia_gpu = mkIf cfg.monitoring.enable {
      enable = true;
      port = 9835;
    };

    # GPU persistence daemon
    systemd.services.nvidia-persistenced = mkIf cfg.nvidia.enable {
      description = "NVIDIA Persistence Daemon";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "forking";
        Restart = "always";
        PIDFile = "/var/run/nvidia-persistenced/nvidia-persistenced.pid";
        ExecStart = "${config.hardware.nvidia.package.bin}/bin/nvidia-persistenced --verbose";
        ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /var/run/nvidia-persistenced";
      };
    };

    # Optimize GPU performance
    boot.kernelParams = [
      "nvidia-drm.modeset=1"
      "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    ];

    # Increase shared memory for multi-GPU workloads
    boot.kernel.sysctl = {
      "kernel.shm_rmid_forced" = 0;
      "kernel.shmmax" = 68719476736; # 64GB
      "kernel.shmall" = 4294967296;
    };

    # GPU memory and compute mode settings
    systemd.services.nvidia-gpu-setup = mkIf cfg.nvidia.enable {
      description = "Setup NVIDIA GPU compute mode";
      wantedBy = [ "multi-user.target" ];
      after = [ "nvidia-persistenced.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Set compute mode (0=Default, 1=Exclusive_Thread, 2=Prohibited, 3=Exclusive_Process)
        ${config.hardware.nvidia.package.bin}/bin/nvidia-smi -c 0
        
        # Enable persistence mode
        ${config.hardware.nvidia.package.bin}/bin/nvidia-smi -pm 1
        
        # Set power limit (adjust based on your hardware)
        # ${config.hardware.nvidia.package.bin}/bin/nvidia-smi -pl 250
        
        # Set memory and graphics clocks (uncomment and adjust as needed)
        # ${config.hardware.nvidia.package.bin}/bin/nvidia-smi -ac 5001,1400
      '';
    };

    # User groups for GPU access
    users.groups.gpu = { };

    # Udev rules for GPU devices
    services.udev.extraRules = ''
      # NVIDIA GPU devices
      KERNEL=="nvidia", RUN+="${pkgs.coreutils}/bin/chmod 666 /dev/nvidia*"
      KERNEL=="nvidia_uvm", RUN+="${pkgs.coreutils}/bin/chmod 666 /dev/nvidia-uvm*"
      KERNEL=="nvidia-modeset", RUN+="${pkgs.coreutils}/bin/chmod 666 /dev/nvidia-modeset"
      
      # Add users to gpu group automatically
      KERNEL=="nvidia*", RUN+="${pkgs.coreutils}/bin/chgrp gpu /dev/%k"
    '';
  };
}
