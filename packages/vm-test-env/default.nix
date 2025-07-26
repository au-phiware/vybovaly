{ pkgs, installer }:

let
  # Create flake directory structure using linkFarm
  # Use the examples/flakes/minimal as our test flake
  testFlakeDir = ../../nixos-configurations/flakes/minimal;
  testFlakeName = "flake.tar.gz";

  # HTTP directory for miniserve
  httpDir = pkgs.runCommand "vm-netboot-http" { } ''
    mkdir -p $out;
    ln -s ${installer.kernel}/bzImage $out/
    ln -s ${installer.initrd}/initrd $out/
    ln -s ${installer.ipxeScript}/netboot.ipxe $out/
    ${pkgs.gnutar}/bin/tar -czf $out/${testFlakeName} -C ${testFlakeDir} --dereference .;
  '';
in
pkgs.writeShellApplication {
  name = "vm-netboot-test";
  runtimeInputs = with pkgs; [
    openssh
    miniserve
    qemu
    mprocs
    tigervnc
    netcat-gnu
    inetutils
    nixos-install-tools
  ];
  text = builtins.readFile ./vm-netboot-test.sh;
  runtimeEnv = {
    HTTP_DIR = "${httpDir}";
    FLAKE_TARBALL = "${testFlakeName}";
    MPROCS_CONFIG = "${./mprocs.yaml}";
    DEFAULT_CONF = "${./test-params.conf}";
  };
  excludeShellChecks = [ "SC1091" ];
}
