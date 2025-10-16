{ 
    stdenv, 
    lib, 
    fetchFromGitHub, 
    kernel
    }:

stdenv.mkDerivation rec {
  pname = "module-dtbocfg";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "ikwzm";
    repo = "dtbocfg";
    hash = "06207c67bac6978a997b37d6e8843504d6f70a4b";
  };

  sourceRoot = ".";
  nativeBuildInputs = kernel.moduleBuildDependencies;                       # 2

  makeFlags = [
    "KERNELRELEASE=${kernel.modDirVersion}"                                 # 3
    "KERNEL_DIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"    # 4
    "INSTALL_MOD_PATH=$(out)"                                               # 5
  ];

  meta = {
    description = "Kernel module to load DTO at runtime";
    homepage = "https://github.com/ikwzm/dtbocfg";
    platforms = lib.platforms.linux;
  };
}
