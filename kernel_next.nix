# from nixpkgs: https://github.com/nixos/nixpkgs/blob/6c46f55495fcb048e624e18862db8422e4c70ee3/pkgs/os-specific/linux/kernel/linux-rpi.nix
{ stdenv, hostPlatform, lib, buildPackages, fetchFromGitHub, perl, buildLinux, linuxKernel, ... } @ args:

let
base = buildLinux (args // {
  version = "next";
  modDirVersion = "next";
  extraMeta.branch = "next";

  src = builtins.fetchGit {
	url = "git@gitlab.com:ssl-r2d2/linux/linux-next.git";
	ref = "linux-de1-next";
	rev = "47a8d4b89844f5974f634b4189a39d5ccbacd81c";
  };

  kernelPatches = [];

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
