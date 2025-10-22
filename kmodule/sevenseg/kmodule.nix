{ stdenv, lib, fetchFromGitHub, kernel, kmod, gcc }:

stdenv.mkDerivation rec {
  pname = "sevensegmodule";
  version = "0.1";

  src = ./src;

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [
    gcc
  ] ;                       # 2

  makeFlags = [
    "KERNELRELEASE=${kernel.modDirVersion}"                                 # 3
    "KERNEL_DIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"    # 4
    "INSTALL_MOD_PATH=$(out)"                                               # 5
    "ARCH=arm"
    "CROSS_COMPILE=armv7l-unknown-linux-gnueabihf-"
    ''MO=''${out}''
  ];

  installPhase = ''
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build ARCH=arm CROSS_COMPILE=armv7l-unknown-linux-gnueabihf- M=$(pwd) src=$(pwd) INSTALL_MOD_PATH=$out modules_install
  '' ;

  meta = {
    description = "Sample kernel moudl";
    license = lib.licenses.gpl2;
    platforms = lib.platforms.linux;
  };
}