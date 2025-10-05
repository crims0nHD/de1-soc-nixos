final: prev: {
  u-boot-socfpga = final.callPackage ./uboot.nix { };
  bootScript = final.callPackage ./bootScript.nix { };
  tbb_2022 = prev.tbb_2022.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ 
      ./patches/oneTBB/0001-Only-enable-fcf-protection-on-x86-based-processors-1.patch 
    ];  
  });
}
