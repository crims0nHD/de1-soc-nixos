{
  description = "NixOS for Cyclone V DE1-SoC";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      out = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
          crossPkgs = pkgs.pkgsCross.armv7l-hf-multiplatform;


          buildConfigModule = ({ ... }: {
            # cross compile to armv7l-hf-multiplatform
            nixpkgs.buildPlatform = { system = system; };
            nixpkgs.hostPlatform = { system = "armv7l-linux"; config = "armv7l-unknown-linux-gnueabihf"; };
	  });
        in
        {
          packages = {
            linux = crossPkgs.callPackage ./kernel_next.nix { };
            uboot = crossPkgs.callPackage ./uboot.nix { };
            sdImage = self.nixosConfigurations."${system}".fpga.config.system.build.sdImage;
            system = self.nixosConfigurations."${system}".fpga.config.system.build.toplevel;
            deploy = pkgs.writeShellScriptBin "deploy" ''
              if [[ $# != 1 ]]; then
                echo "Usage: $0 IP_ADDR"
                exit 1
              fi
              NIX_SSHOPTS="-l root" ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --target-host $1 --fast --flake .#fpga
            '';
          };

          devShells.default = pkgs.mkShellNoCC {
            OPENOCD = pkgs.openocd;
            buildInputs = with pkgs; [
              picocom
              dnsmasq
              sshfs
              openocd
              dtc

              clang-tools
              ubootTools
              gdb
              nixos-rebuild
              self.packages.${system}.deploy
            ];
          };

	

	      nixosConfigurations.fpga = nixpkgs.lib.nixosSystem {
		modules = [
		  buildConfigModule
		  ({ pkgs, config, ... }: {
		    boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.callPackage ./kernel_next.nix { });
		    nixpkgs.overlays = [ self.overlays.default ];

		    system.stateVersion = "25.05";
		  })
		  ./sd-image.nix
		  ./fpga-sdimage.nix
		  ./system.nix
		];
	      };

        };
    in
    (flake-utils.lib.eachDefaultSystem out) // {
	      overlays.default = import ./overlay.nix;
    };
}
