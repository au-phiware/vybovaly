# modules/ml-stack.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.ml-stack;

  # Python environment with ML packages
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    # Core ML libraries
    torch
    torchvision
    torchaudio
    tensorflow
    tensorboard
    jax
    jaxlib

    # Data science
    numpy
    pandas
    scipy
    matplotlib
    seaborn
    scikit-learn
    scikit-image
    opencv4
    pillow

    # Deep learning utilities
    transformers
    datasets
    tokenizers
    accelerate
    wandb
    tensorboard

    # Jupyter and development
    jupyter
    ipykernel
    ipywidgets
    notebook
    jupyterlab

    # Utilities
    tqdm
    click
    typer
    pyyaml
    toml
    requests
    aiohttp

    # GPU utilities
    pynvml
    gpustat
  ]);

in
{
  options.services.ml-stack = {
    enable = mkEnableOption "ML/AI development stack";

    jupyter = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable JupyterLab server";
      };

      port = mkOption {
        type = types.int;
        default = 8888;
        description = "JupyterLab server port";
      };

      password = mkOption {
        type = types.str;
        default = "";
        description = "JupyterLab password hash";
      };
    };

    mlflow = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable MLflow tracking server";
      };

      port = mkOption {
        type = types.int;
        default = 5000;
        description = "MLflow server port";
      };
    };

    tensorboard = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable TensorBoard service";
      };

      port = mkOption {
        type = types.int;
        default = 6006;
        description = "TensorBoard port";
      };

      logdir = mkOption {
        type = types.str;
        default = "/var/lib/tensorboard/logs";
        description = "TensorBoard log directory";
      };
    };

    vscode-server = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable VS Code server";
      };

      port = mkOption {
        type = types.int;
        default = 8080;
        description = "VS Code server port";
      };
    };

    datasets = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Setup common dataset directories";
      };

      path = mkOption {
        type = types.str;
        default = "/data";
        description = "Base path for datasets";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install ML stack packages
    environment.systemPackages = with pkgs; [
      pythonEnv

      # Development tools
      git
      git-lfs
      tmux
      screen
      htop
      nvtopPackages.full

      # Data tools
      dvc
      rclone
      rsync

      # Container tools
      docker-compose
      podman

      # VS Code server (if enabled)
      (mkIf cfg.vscode-server.enable code-server)
    ];

    # JupyterLab service
    systemd.services.jupyterlab = mkIf cfg.jupyter.enable {
      description = "JupyterLab Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "jupyter";
        Group = "jupyter";
        WorkingDirectory = "/home/jupyter";
        Restart = "always";
        RestartSec = 5;
      };

      script = ''
        export CUDA_VISIBLE_DEVICES=all
        ${pythonEnv}/bin/jupyter lab \
          --ip=0.0.0.0 \
          --port=${toString cfg.jupyter.port} \
          --no-browser \
          --allow-root \
          --NotebookApp.token= \
          ${optionalString (cfg.jupyter.password != "") "--NotebookApp.password='${cfg.jupyter.password}'"}
      '';
    };

    # MLflow tracking server
    systemd.services.mlflow = mkIf cfg.mlflow.enable {
      description = "MLflow Tracking Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "mlflow";
        Group = "mlflow";
        WorkingDirectory = "/var/lib/mlflow";
        Restart = "always";
        RestartSec = 5;
      };

      script = ''
        ${pythonEnv}/bin/mlflow server \
          --host 0.0.0.0 \
          --port ${toString cfg.mlflow.port} \
          --backend-store-uri sqlite:///var/lib/mlflow/mlflow.db \
          --default-artifact-root /var/lib/mlflow/artifacts
      '';
    };

    # TensorBoard service
    systemd.services.tensorboard = mkIf cfg.tensorboard.enable {
      description = "TensorBoard Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "tensorboard";
        Group = "tensorboard";
        Restart = "always";
        RestartSec = 5;
      };

      script = ''
        ${pythonEnv}/bin/tensorboard \
          --logdir ${cfg.tensorboard.logdir} \
          --host 0.0.0.0 \
          --port ${toString cfg.tensorboard.port} \
          --reload_interval 30
      '';
    };

    # VS Code server service
    systemd.services.code-server = mkIf cfg.vscode-server.enable {
      description = "VS Code Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = "code-server";
        Group = "code-server";
        WorkingDirectory = "/home/code-server";
        Restart = "always";
        RestartSec = 5;
        Environment = [
          "PASSWORD="
          "SUDO_CODER=false"
        ];
      };

      script = ''
        ${pkgs.code-server}/bin/code-server \
          --bind-addr 0.0.0.0:${toString cfg.vscode-server.port} \
          --auth none \
          --disable-telemetry
      '';
    };

    # Create service users
    users.users = {
      jupyter = mkIf cfg.jupyter.enable {
        isSystemUser = true;
        group = "jupyter";
        home = "/home/jupyter";
        createHome = true;
        extraGroups = [ "gpu" "docker" ];
      };

      mlflow = mkIf cfg.mlflow.enable {
        isSystemUser = true;
        group = "mlflow";
        home = "/var/lib/mlflow";
        createHome = true;
      };

      tensorboard = mkIf cfg.tensorboard.enable {
        isSystemUser = true;
        group = "tensorboard";
        home = "/var/lib/tensorboard";
        createHome = true;
      };

      code-server = mkIf cfg.vscode-server.enable {
        isSystemUser = true;
        group = "code-server";
        home = "/home/code-server";
        createHome = true;
        extraGroups = [ "gpu" "docker" ];
      };
    };

    users.groups = {
      jupyter = mkIf cfg.jupyter.enable { };
      mlflow = mkIf cfg.mlflow.enable { };
      tensorboard = mkIf cfg.tensorboard.enable { };
      code-server = mkIf cfg.vscode-server.enable { };
    };

    # Create directories
    systemd.tmpfiles.rules = [
      "d /var/lib/mlflow 0755 mlflow mlflow -"
      "d /var/lib/mlflow/artifacts 0755 mlflow mlflow -"
      "d ${cfg.tensorboard.logdir} 0755 tensorboard tensorboard -"
    ] ++ (optionals cfg.datasets.enable [
      "d ${cfg.datasets.path} 0755 root root -"
      "d ${cfg.datasets.path}/datasets 0755 root root -"
      "d ${cfg.datasets.path}/models 0755 root root -"
      "d ${cfg.datasets.path}/experiments 0755 root root -"
    ]);

    # Firewall rules
    networking.firewall.allowedTCPPorts = [
      (mkIf cfg.jupyter.enable cfg.jupyter.port)
      (mkIf cfg.mlflow.enable cfg.mlflow.port)
      (mkIf cfg.tensorboard.enable cfg.tensorboard.port)
      (mkIf cfg.vscode-server.enable cfg.vscode-server.port)
    ];

    # Environment variables for all users
    environment.variables = {
      CUDA_VISIBLE_DEVICES = "all";
      PYTHONPATH = "${pythonEnv}/${pythonEnv.sitePackages}";
    };

    # Shell aliases for convenience
    environment.shellAliases = {
      gpu-status = "nvidia-smi";
      gpu-top = "nvtop";
      jupyter-logs = "journalctl -u jupyterlab -f";
      mlflow-logs = "journalctl -u mlflow -f";
      tb-logs = "journalctl -u tensorboard -f";
    };
  };
}
