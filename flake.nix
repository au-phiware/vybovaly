{
  description = "Vybovaly Automated Installation System";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # Flake utilities
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
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
                curl
                wget
                git
                parted
                nixos-install-tools
                htop
                lsof
                file
                tree
                iproute2
                iputils
                nettools
                dhcpcd
              ];

              more = with pkgs; minimal ++ [
                disko
                tmux
                vim
                pciutils
                usbutils
                bind.dnsutils
                tcpdump
                nmap
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
              #users.users.root.password = "not this";

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
                "ip=dhcp" # Force IP configuration via kernel parameter
              ];

              # Enable more verbose boot for debugging
              boot.initrd.verbose = true;
            };

            # Build the netboot system
            netbootSystem = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [ netbootConfig ];
            };

          in
          {
            # Netboot outputs (for iPXE/PXE)
            kernel = netbootSystem.config.system.build.kernel;
            initrd = netbootSystem.config.system.build.netbootRamdisk;
            squashfs = netbootSystem.config.system.build.squashfsStore;
            ipxeScript = pkgs.runCommand "vybovaly-ipxe-build" {} ''
              mkdir -p $out
              {
                cat ${./ipxe/netboot.ipxe}
                tail -n +2 ${netbootSystem.config.system.build.netbootIpxeScript}/netboot.ipxe
              } > $out/netboot.ipxe
            '';

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
            cachix
            nil # Nix language server
            libsecret

            # Network boot tools
            dnsmasq
            tftp-hpa
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

          # Development scripts
          devScripts = {
            # Build all variants
            build-all = pkgs.writeShellScriptBin "build-all" ''
              set -euo pipefail
              echo "Building all installer variants..."

              for variant in minimal more; do
                echo "Building variant: $variant"
                nix build .#installer-$variant-kernel -o result-$variant-kernel
                nix build .#installer-$variant-initrd -o result-$variant-initrd
              done

              echo "All variants built successfully!"
            '';

            # Run Linters
            lint = pkgs.writeShellScriptBin "lint" ''
              ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt -- **/*.nix
              ${pkgs.nix}/bin/nix flake check
            '';

            pin = pkgs.writeShellScriptBin "pin" ''
              ${pkgs.cachix}/bin/cachix pin vybovaly $1 $(${pkgs.nix}/bin/nix build .#default --print-out-paths) --artifact bzImage --artifact checksums.txt --artifact initrd --artifact netboot.ipxe
            '';

            # Clean build artifacts
            clean-build = pkgs.writeShellScriptBin "clean-build" ''
              echo "Cleaning build artifacts..."

              # Remove result symlinks
              rm -f result-*

              # Remove build directory
              rm -rf build/

              echo "Clean completed!"
            '';
          };

          minimal = buildInstallerImage { variant = "minimal"; };
          more = buildInstallerImage { variant = "more"; };
        in
        {
          # Build artifacts for easy access
          packages = {
            # Release bundle - all three artifacts with checksums
            default = pkgs.runCommand "vybovaly-build" { } ''
              mkdir -p $out

              # Copy artifacts
              cp ${minimal.kernel}/bzImage $out/bzImage
              cp ${minimal.initrd}/initrd $out/initrd
              cp ${minimal.ipxeScript}/netboot.ipxe $out/netboot.ipxe

              # Generate checksums
              cd $out
              sha256sum bzImage initrd netboot.ipxe > checksums.txt
            '';

            # VM test environment
            vm-test-env = vmTestEnvironment;
          } // devScripts;

          # Development shell
          devShells.default = pkgs.mkShell {
            buildInputs = devTools ++ (builtins.attrValues devScripts);

            shellHook = ''
              export CACHIX_AUTH_TOKEN=$(${pkgs.libsecret}/bin/secret-tool lookup vybovaly.cachix.org CACHIX_AUTH_TOKEN)

              echo "🚀 Vybovaly Development Environment"
              echo "Available commands:"
              echo "  build-all           - Build all installer variants"
              echo "  clean-build         - Clean all build artifacts"
              echo "  lint                - Run all linters"
              echo "  pin version         - Pin build on vybovaly.cachix.org"
              echo ""
              echo "Development tools available:"
              echo "  nix, nixpkgs-fmt, nil (LSP)"
              echo "  dnsmasq, miniserve, qemu"
              echo "  shellcheck, jq, curl, git"
              echo ""
              echo "VM test environment:"
              echo "  nix run .#vm-test-env"
              echo ""

              # Set up git hooks if not already done
              if [[ ! -e .git/hooks/pre-commit ]]; then
                echo "Setting up git pre-commit hooks..."
                ln -s ${devScripts.lint}/bin/lint .git/hooks/pre-commit
              fi
            '';
          };

          # CI/CD checks
          checks = {
            # Shell script validation
            shellcheck = pkgs.runCommand "vybovaly-shellcheck" { } ''
              ${pkgs.findutils}/bin/find ${self} -name "*.sh" -exec ${pkgs.shellcheck}/bin/shellcheck {} \;
              touch $out
            '';

            # Nix formatting check
            nixpkgs-fmt = pkgs.runCommand "vybovaly-nixpkgs-fmt-check" { } ''
              ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${self}/**/*.nix
              touch $out
            '';
          };

          # Apps for easy execution
          apps = {
            vybovaly-installer = {
              type = "app";
              program = "${minimal.config.system.build.vybovaly-installer}/bin/vybovaly-installer";
              meta = {
                description = "Automated NixOS installer for network deployment";
                homepage = "https:///github.com/au-phiware/vybovaly-installer";
                license = pkgs.lib.licenses.mit;
                maintainers = [ ];
              };
            };
          };
        }
      ) // {
        # NixOS modules for easy import
        nixosModules = {
          installer = import ./installer;
          gpu-server = import ./modules/gpu.nix;
          ml-stack = import ./modules/ml-stack.nix;
        };

        # Overlay for custom packages
        overlays.default = final: prev: {
          vybovaly-installer = {
            buildInstallerImage = self.packages.${final.system}.installer-minimal-kernel;
          };
        };
      };
  }
