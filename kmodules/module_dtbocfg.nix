{ 
    stdenv, 
    lib, 
    fetchFromGitHub, 
    kernel,
    gcc
    }:

stdenv.mkDerivation rec {
  pname = "module-dtbocfg";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "ikwzm";
    repo = "dtbocfg";
    rev = "06207c67bac6978a997b37d6e8843504d6f70a4b";
    hash = "sha256-HSiFDFg9dZmLga8uLCBT55hI1pVPiryOs1QdM7jbZ4E=";
  };

  sourceRoot = "source";
  nativeBuildInputs = kernel.moduleBuildDependencies ++ [
    gcc
  ];                       # 2

  buildInputs = [] ;

  makeFlags = [
    "KERNEL_SRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"    # 4
    "ARCH=arm"
    "CROSS_COMPILE=armv7l-unknown-linux-gnueabihf-"
    ''MO=''${out}''
  ];

  installPhase = ''
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build ARCH=arm CROSS_COMPILE=armv7l-unknown-linux-gnueabihf- M=$(pwd) src=$(pwd) INSTALL_MOD_PATH=$out modules_install
  '' ;

  meta = {
    description = "Kernel module to load DTO at runtime";
    homepage = "https://github.com/ikwzm/dtbocfg";
    platforms = lib.platforms.linux;
  };
}
