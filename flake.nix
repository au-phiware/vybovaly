{
  description = "Vybovaly Automated Installation System";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # Flake utilities
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        # Custom builder for NixOS installer images
        buildInstallerImage = { variant ? "minimal" }:
          let
            # Import our installer module
            installerModule = ./installer;

            # Variant-specific package sets
            variantPackages = rec {
              minimal = with pkgs; [
                curl wget git parted nixos-install-tools
                htop lsof file tree
                iproute2 iputils nettools dhcpcd
              ];

              more = with pkgs; minimal ++ [
                disko
                tmux vim
                pciutils usbutils
                bind.dnsutils tcpdump nmap
              ];
            };

            netbootConfig = { config, lib, pkgs, ... }: {
              imports = [
                installerModule
              ];

              # Enable our auto-installer service
              services.vybovaly-installer.enable = true;

              # Set the NixOS state version for the installer
              system.stateVersion = "25.05";

              # Variant-specific packages plus network debugging tools
              environment.systemPackages = variantPackages.${variant} or variantPackages.minimal;

              # Specify vyb.ssh_key and just use ssh
              #users.users.root.password = "vybovaly";

              # Network configuration optimized for automation
              networking = {
                nameservers = [ "8.8.8.8" "8.8.4.4" "1.1.1.1" ];
              };

              # Console and serial configuration
              console.keyMap = "us";
              boot.kernelParams = [
                "console=tty0"
                "console=ttyS0,115200n8"
                "boot.shell_on_fail"
                "systemd.log_level=debug"
                "systemd.log_target=console"
                "ip=dhcp"  # Force IP configuration via kernel parameter
              ];

              # Enable more verbose boot for debugging
              boot.initrd.verbose = true;
            };

            # Build the netboot system
            netbootSystem = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [ netbootConfig ];
            };

          in {
            # Netboot outputs (for iPXE/PXE)
            kernel = netbootSystem.config.system.build.kernel;
            initrd = netbootSystem.config.system.build.netbootRamdisk;
            squashfs = netbootSystem.config.system.build.squashfsStore;
            ipxeScript = netbootSystem.config.system.build.netbootIpxeScript;

            # For VM testing
            vm = netbootSystem.config.system.build.vm;

            # System configuration for inspection
            config = netbootSystem.config;
          };

        # Development tools
        devTools = with pkgs; [
          # Nix tools
          nix
          nixpkgs-fmt
          nil # Nix language server

          # Network boot tools
          dnsmasq
          tftp-hpa
          nginx
          miniserve

          # Network testing
          curl
          wget
          tcpdump
          nmap
          netcat

          # VM and testing
          qemu
          qemu_kvm
          tigervnc

          # Development utilities
          git
          jq
          yq
          mprocs

          # Linters
          shellcheck
          shfmt
          mdl

          # File utilities
          file
          tree
          fd
          ripgrep

          # Process management
          htop
          lsof

          # Container tools (for testing)
          docker
          docker-compose

          # iPXE development
          ipxe
        ];

        # VM test environment (built from separate package)
        vmTestEnvironment = pkgs.callPackage ./packages/vm-test-env {
          installer = buildInstallerImage { variant = "minimal"; };
        };

        # Test scripts
        testScripts = {
          # Build all variants
          build-all = pkgs.writeShellScriptBin "build-all-variants" ''
            set -euo pipefail
            echo "Building all installer variants..."

            for variant in minimal more; do
              echo "Building variant: $variant"
              nix build .#installer-$variant-kernel -o result-$variant-kernel
              nix build .#installer-$variant-initrd -o result-$variant-initrd
            done

            echo "All variants built successfully!"
          '';

          # Clean build artifacts
          clean-build = pkgs.writeShellScriptBin "clean-build" ''
            set -euo pipefail

            echo "Cleaning build artifacts..."

            # Remove result symlinks
            rm -f result-*

            # Remove build directory
            rm -rf build/

            # Remove test files
            rm -f test-disk.qcow2

            echo "Clean completed!"
          '';
        };

      in {
        # Build artifacts for easy access
        packages =
          let
            minimal = buildInstallerImage { variant = "minimal"; };
            more = buildInstallerImage { variant = "more"; };
          in {
            # Main outputs - the three key artifacts for releases
            bzImage = minimal.kernel;
            initrd = minimal.initrd;
            netboot-ipxe = minimal.ipxeScript;

            # Release bundle - all three artifacts with checksums
            release-artifacts = pkgs.runCommand "vybovaly-release-artifacts" {} ''
              mkdir -p $out

              # Copy artifacts
              cp ${minimal.kernel}/bzImage $out/bzImage
              cp ${minimal.initrd}/initrd $out/initrd
              cp ${minimal.ipxeScript}/netboot.ipxe $out/netboot.ipxe

              # Generate checksums
              cd $out
              sha256sum bzImage initrd netboot.ipxe > checksums.txt
            '';

            # Variant-specific packages (for advanced users)
            installer-minimal-kernel = minimal.kernel;
            installer-minimal-initrd = minimal.initrd;
            installer-minimal-netboot = minimal.ipxeScript;

            installer-more-kernel = more.kernel;
            installer-more-initrd = more.initrd;
            installer-more-netboot = more.ipxeScript;

            # VM test environment
            vm-test-env = vmTestEnvironment;

            # Default package
            default = minimal.kernel;
          } // testScripts;

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = devTools;

          shellHook = ''
            echo "🚀 Vybovaly Development Environment"
            echo "Available commands:"
            echo "  build-all-variants  - Build all installer variants"
            echo "  test-vm [variant]   - Start test VM (variants: minimal, more)"
            echo "  test-pxe-server     - Start HTTP server for PXE testing"
            echo "  clean-build         - Clean all build artifacts"
            echo ""
            echo "Development tools available:"
            echo "  nix, nixpkgs-fmt, nil (LSP)"
            echo "  dnsmasq, nginx, qemu"
            echo "  shellcheck, jq, curl, git"
            echo ""
            echo "Quick start:"
            echo "  1. test-pxe-server 8080"
            echo "  2. test-vm minimal"
            echo "  3. Point VM network boot to http://localhost:8080/nixos-install.ipxe"
            echo ""

            # Set up git hooks if not already done
            if [[ ! -f .git/hooks/pre-commit ]]; then
              echo "Setting up git pre-commit hooks..."
              cat > .git/hooks/pre-commit << 'EOF'
            #!/usr/bin/env bash
            # Format Nix files
            nixpkgs-fmt -- **/*.nix

            # Check shell scripts
            find . -name "*.sh" -exec shellcheck {} \;

            # Validate flake
            nix flake check
            EOF
              chmod +x .git/hooks/pre-commit
            fi
          '';
        };

        # CI/CD checks
        checks = {
          # Validate flake
          flake-check = pkgs.runCommand "flake-check" {} ''
            cd ${self}
            ${pkgs.nix}/bin/nix --extra-experimental-features "nix-command flakes" flake check
            touch $out
          '';

          # Build all variants
          build-minimal = self.packages.${system}.installer-minimal-kernel;
          build-more = self.packages.${system}.installer-more-kernel;

          # Shell script validation
          shellcheck = pkgs.runCommand "shellcheck" {} ''
            ${pkgs.findutils}/bin/find ${./.} -name "*.sh" -exec ${pkgs.shellcheck}/bin/shellcheck {} \;
            touch $out
          '';

          # Nix formatting check
          nixpkgs-fmt = pkgs.runCommand "nixpkgs-fmt-check" {} ''
            ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${self}/**/*.nix
            touch $out
          '';
        };

        # Apps for easy execution
        apps = {
          # Build specific variant
          build-minimal = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "build-minimal" ''
              nix build .#installer-minimal-kernel -o result-minimal-kernel
              nix build .#installer-minimal-initrd -o result-minimal-initrd
              echo "Netboot build complete"
            '';
          };
        };
      }
    ) // {
      # NixOS modules for easy import
      nixosModules = {
        gpu-server = import ./modules/gpu.nix;
        ml-stack = import ./modules/ml-stack.nix;
        monitoring = import ./modules/monitoring.nix;
        installer = import ./installer;
      };

      # Example configurations
      nixosConfigurations = {
        # Example GPU server configuration
        example-gpu-server = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./examples/gpu-server-configuration.nix
            self.nixosModules.gpu-server
            self.nixosModules.ml-stack
            self.nixosModules.monitoring
          ];
        };
      };

      # Overlay for custom packages
      overlays.default = final: prev: {
        vybovaly-installer = {
          buildInstallerImage = self.packages.${final.system}.installer-minimal-kernel;
        };
      };
    };
}
