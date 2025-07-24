{
  description = "GPU compute server with Jupyter notebook environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      nixosConfigurations.gpu-compute = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          # Import the GPU and ML stack modules
          ../../../modules/gpu.nix
          ../../../modules/ml-stack.nix

          {
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

            # Enable ML stack with Jupyter
            services.gpu-server = {
              enable = true;
              nvidia.enable = true;
              cuda.enable = true;
              docker.enable = true;
              monitoring.enable = true;
            };

            # Additional packages for GPU compute
            environment.systemPackages = with pkgs; [
              # System monitoring
              htop
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
            ];

            # Ensure data directories have proper permissions
            systemd.tmpfiles.rules = [
              "d /data 0755 root root -"
              "d /data/datasets 0755 root users -"
              "d /data/models 0755 root users -"
              "d /data/experiments 0755 root users -"
              "d /data/notebooks 0755 root users -"
            ];

            boot.loader.grub = {
              enable = true;
              efiSupport = false;
              device = "/dev/vda";
              useOSProber = false;
            };

            # Filesystem configuration (should match disko labels)
            fileSystems."/" =
              {
                device = "/dev/disk/by-label/nixos";
                fsType = "ext4";
              };

            fileSystems."/boot" =
              {
                device = "/dev/disk/by-label/boot";
                fsType = "ext4";
              };

            # Basic system configuration
            system.stateVersion = "25.05";
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
