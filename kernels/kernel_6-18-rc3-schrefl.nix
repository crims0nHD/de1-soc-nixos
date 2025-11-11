# from nixpkgs: https://github.com/nixos/nixpkgs/blob/6c46f55495fcb048e624e18862db8422e4c70ee3/pkgs/os-specific/linux/kernel/linux-rpi.nix
{ stdenv, hostPlatform, lib, buildPackages, fetchurl, perl, buildLinux, linuxKernel, ... } @ args:

let
version = "6.18.0-rc3";
base = buildLinux (args // {
  version = version;
  modDirVersion = version;
  extraMeta.branch = version;

  src = fetchurl {
  	url = "git+https://gitlab.com/ssl-r2d2/linux/linux-6.18-rc3-patched.git?ref=b4/rust_miscdevice_registrationdata";
	  hash = "";
  };

  kernelPatches = [
  ];

  extraMakeFlags = [
    "LLVM=1"
    "ARCH=arm"
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
  configfile = ./socfpga_kconfig_6-18-rc1;
  allowImportFromDerivation = true;
}
