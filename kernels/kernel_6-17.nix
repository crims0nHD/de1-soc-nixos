# from nixpkgs: https://github.com/nixos/nixpkgs/blob/6c46f55495fcb048e624e18862db8422e4c70ee3/pkgs/os-specific/linux/kernel/linux-rpi.nix
{ stdenv, hostPlatform, lib, buildPackages, fetchurl, perl, buildLinux, linuxKernel, ... } @ args:

let
version = "6.17";
base = buildLinux (args // {
  version = version;
  modDirVersion = version;
  extraMeta.branch = version;

  src = fetchurl {
  	url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.17.tar.xz";
	hash = "sha256-m2BxZqHJmdgyYJgSEiL+sICiCjJTl1/N+i3pa6f3V6c=";
  };

  kernelPatches = [
  ];

  defconfig = "socfpga_defconfig";

  features = {
    efiBootStub = false;
    iwlwifi = false;
  } // (args.features or { });
} // args.argsOverride or { });
in
linuxKernel.manualConfig {
  inherit stdenv;
  inherit (base) src version;
  configfile = ./socfpga_kconfig;
  allowImportFromDerivation = true;
}
