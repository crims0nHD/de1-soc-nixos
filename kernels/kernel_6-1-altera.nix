# from nixpkgs: https://github.com/nixos/nixpkgs/blob/6c46f55495fcb048e624e18862db8422e4c70ee3/pkgs/os-specific/linux/kernel/linux-rpi.nix
{ stdenv, hostPlatform, lib, buildPackages, fetchFromGitHub, perl, buildLinux, linuxKernel, ... } @ args:

let
  modDirVersion = "6.1.68";
  tag = "d9816a2213846a68a462dc8b0cbc432d79b03114";

base = buildLinux (args // {
  version = "${modDirVersion}";
  inherit modDirVersion;
  extraMeta.branch = "6.1";

  src = fetchFromGitHub {
    owner = "altera-opensource";
    repo = "linux-socfpga";
    rev = tag;
    hash = "sha256-Lg3ANDQ6qJwSKF4yZqRu5Ag6wg4h3x/D1Tl+xkrvouk=";
  };

  kernelPatches = [{
    name = "fix-nocache";
    patch = ./patches/linux/0001-Fix-compilation-_nocache-variants-are-gone-since-201.patch;
  }];

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
