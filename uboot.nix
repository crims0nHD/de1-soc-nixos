{
  # buildUBoot,
  pkgs,
  fetchFromGitHub 
}:
let 
  buildUBoot = (pkgs.callPackage ./custom-uboot.nix {}).buildUBoot;
in
buildUBoot {
  src = fetchFromGitHub {
    owner = "altera-fpga";
    repo = "u-boot-socfpga";
    rev = "08197d3d7344b6d32f3ac6154771f2412a50d967";
    sha256 = "sha256-mFcXkuCHjRA4RbnccvJgzcMg0J1lFTF7FVV9nfiwiL0=";
  };
  version = "socfpga_25.04";

  defconfig = "socfpga_de1_soc_defconfig";
  filesToInstall = [ "spl/u-boot-spl" "u-boot" "u-boot-with-spl.sfp" ];
  extraConfig = ''
    CONFIG_USE_BOOTCOMMAND=y
    CONFIG_WATCHDOG=y
    CONFIG_BOOTCOMMAND="if ext4load mmc 0:2 ''${scriptaddr} /boot/u-boot.scr; then source ''${scriptaddr}; fi; bridge enable; run distro_bootcmd"
  '';

  extraPatches = [
    # https://lists.denx.de/pipermail/u-boot/2023-February/508674.html
    # NOTE: this patch was implemented in 2023, keep it until testing has finished
    #./patches/u-boot/0001-socfpga-fix-the-serial-console-on-DE1-SoC.patch
    
    # Linux was rebooting after a few seconds. This is unclear whether it
    # should actually be in u-boot, since it's only relevant to Linux, and
    # perhaps Linux should transition to a different device tree. It's done
    # this way because it's Easier(tm) but we might change it.
    ./patches/u-boot/0002-Enable-the-watchdog-is-this-a-good-idea.patch
  ];
}
