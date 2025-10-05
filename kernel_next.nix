# from nixpkgs: https://github.com/nixos/nixpkgs/blob/6c46f55495fcb048e624e18862db8422e4c70ee3/pkgs/os-specific/linux/kernel/linux-rpi.nix
{ stdenv, hostPlatform, lib, buildPackages, fetchFromGitHub, perl, buildLinux, linuxKernel, clangStdenv, ... } @ args:

let
base = buildLinux (args // {
  version = "6.17.0-next-20251003";
  modDirVersion = "6.17.0-next-20251003";
  extraMeta.branch = "6.17.0-next-20251003";

  src = builtins.fetchGit {
	url = "git@gitlab.com:ssl-r2d2/linux/linux-next.git";
	ref = "linux-de1-next";
	rev = "47a8d4b89844f5974f634b4189a39d5ccbacd81c";
  };

  kernelPatches = [];

  defconfig = "socfpga_defconfig";

  features = {
    rust = true;
    efiBootStub = false;
    iwlwifi = false;
  } // (args.features or { });
} // args.argsOverride or { });
in
linuxKernel.manualConfig {
  stdenv = clangStdenv;
  inherit (base) src version;
  configfile = ./socfpga_kconfig;
  allowImportFromDerivation = true;
}
