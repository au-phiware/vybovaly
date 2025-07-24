{
  description = "GPU compute server with Jupyter notebook environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    vybovaly-installer = {
      url = "path:../../..";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, vybovaly-installer }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.gpu-compute = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          # Import the GPU and ML stack modules
          vybovaly-installer.nixosModules.gpu-server
          vybovaly-installer.nixosModules.ml-stack

          {
            # Basic system configuration
            system.stateVersion = "24.05";

            # Enable flakes
            nix.settings.experimental-features = [ "nix-command" "flakes" ];

            # Network configuration
            networking.hostName = "gpu-compute";
            networking.firewall.enable = true;

            # Enable SSH
            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = false;
                PermitRootLogin = "no";
              };
            };

            # Create a user for ML work
            users.users.mluser = {
              isNormalUser = true;
              extraGroups = [ "wheel" "gpu" "docker" ];
              openssh.authorizedKeys.keys = [
                # Add your SSH public key here
                # "ssh-rsa AAAAB3NzaC1yc2EAAAA..."
              ];
            };

            # Enable ML stack with Jupyter
            services.ml-stack = {
              enable = true;
              jupyter = {
                enable = true;
                port = 8888;
                # Generate password hash with: python3 -c "from jupyter_server.auth import passwd; print(passwd('your-password'))"
                password = ""; # Leave empty for no password (not recommended for production)
              };
              mlflow = {
                enable = true;
                port = 5000;
              };
              tensorboard = {
                enable = true;
                port = 6006;
                logdir = "/data/experiments/tensorboard";
              };
              vscode-server = {
                enable = true;
                port = 8080;
              };
              datasets = {
                enable = true;
                path = "/data";
              };
            };

            # Additional packages for GPU compute
            environment.systemPackages = with pkgs; [
              # System monitoring
              htop
              nvtop
              iotop
              tmux
              screen

              # Development tools
              git
              git-lfs
              vim
              neovim
              curl
              wget

              # GPU utilities
              cudatoolkit
              nvidia-docker
            ];

            # Docker for containerized ML workloads
            virtualisation.docker = {
              enable = true;
              enableNvidia = true;
            };

            # Ensure data directories have proper permissions
            systemd.tmpfiles.rules = [
              "d /data 0755 root root -"
              "d /data/datasets 0755 root users -"
              "d /data/models 0755 root users -"
              "d /data/experiments 0755 root users -"
              "d /data/notebooks 0755 root users -"
            ];

            # Performance optimizations for ML workloads
            boot.kernel.sysctl = {
              # Increase shared memory for large datasets
              "kernel.shmmax" = 68719476736; # 64GB
              "kernel.shmall" = 4294967296;  # 16GB in pages
              
              # Network optimizations
              "net.core.rmem_max" = 134217728;
              "net.core.wmem_max" = 134217728;
              "net.ipv4.tcp_rmem" = "4096 65536 134217728";
              "net.ipv4.tcp_wmem" = "4096 65536 134217728";
            };
          }
        ];
      };

      # Provide a shell for development
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          python3
          jupyter
          git
        ];

        shellHook = ''
          echo "GPU Compute Development Environment"
          echo "=================================="
          echo "Available services:"
          echo "- JupyterLab: http://localhost:8888"
          echo "- MLflow: http://localhost:5000"
          echo "- TensorBoard: http://localhost:6006"
          echo "- VS Code Server: http://localhost:8080"
          echo ""
          echo "Data directories:"
          echo "- /data/datasets - Store your datasets here"
          echo "- /data/models - Save trained models here"
          echo "- /data/experiments - Experiment logs and outputs"
          echo "- /data/notebooks - Jupyter notebooks"
        '';
      };
    };
}