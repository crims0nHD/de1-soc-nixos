# Adapted from https://github.com/nixos/nixpkgs/blob/0c67f190b188ba25fc087bfae33eedcc5235a762/nixos/modules/installer/sd-card/sd-image.nix
# We need to build an image with a RAW partition with type 0xA2. There is no
# need for a FAT32 partition as built by default, so that code has been repurposed.

# This module creates a bootable SD card image containing the given NixOS
# configuration. The generated image is MBR partitioned, with a raw SPL
# partition, and ext4 root partition. The generated image is sized to fit its
# contents, and a boot script automatically resizes the root partition to fit
# the device on the first boot.
#
# The derivation for the SD image will be placed in
# config.system.build.sdImage

{ config, lib, pkgs, modulesPath, ... }:

with lib;

let
  rootfsImage = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" ({
    inherit (config.sdImage) storePaths;
    compressImage = config.sdImage.compressImage;
    populateImageCommands = config.sdImage.populateRootCommands;
    volumeLabel = "NIXOS_SD";
  } // optionalAttrs (config.sdImage.rootPartitionUUID != null) {
    uuid = config.sdImage.rootPartitionUUID;
  });
in
{
  options.sdImage = {
    imageName = mkOption {
      default = "${config.sdImage.imageBaseName}-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img";
      description = lib.mdDoc ''
        Name of the generated image file.
      '';
    };

    imageBaseName = mkOption {
      default = "nixos-sd-image";
      description = lib.mdDoc ''
        Prefix of the name of the generated image file.
      '';
    };

    storePaths = mkOption {
      type = with types; listOf package;
      example = literalExpression "[ pkgs.stdenv ]";
      description = lib.mdDoc ''
        Derivations to be included in the Nix store in the generated SD image.
      '';
    };

    firmwarePartitionOffset = mkOption {
      type = types.int;
      default = 8;
      description = lib.mdDoc ''
        Gap in front of the firmware partition, in mebibytes (1024×1024
        bytes).
        Can be increased to make more space for boards requiring to dd u-boot
        SPL before actual partitions.

        Unless you are building your own images pre-configured with an
        installed U-Boot, you can instead opt to delete the existing `FIRMWARE`
        partition, which is used **only** for the Raspberry Pi family of
        hardware.
      '';
    };

    firmwarePartitionID = mkOption {
      type = types.str;
      default = "0x2178694e";
      description = lib.mdDoc ''
        Partition table ID. This value must be a 32-bit hexadecimal number.
      '';
    };

    rootPartitionUUID = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "14e19a7b-0ae0-484d-9d54-43bd6fdc20c7";
      description = lib.mdDoc ''
        UUID for the filesystem on the main NixOS partition on the SD card.
      '';
    };

    firmwareSize = mkOption {
      type = types.int;
      # As of 2019-08-18 the Raspberry pi firmware + u-boot takes ~18MiB
      default = 30;
      description = lib.mdDoc ''
        Size of the /boot/firmware partition, in megabytes.
      '';
    };

    bootloaderSpl = mkOption {
      type = types.path;
      description = lib.mdDoc ''
        U-Boot SPL to copy to the firmware partition.
      '';
    };

    populateRootCommands = mkOption {
      example = literalExpression "''\${config.boot.loader.generic-extlinux-compatible.populateCmd} -c \${config.system.build.toplevel} -d ./files/boot''";
      description = lib.mdDoc ''
        Shell commands to populate the ./files directory.
        All files in that directory are copied to the
        root (/) partition on the SD image. Use this to
        populate the ./files/boot (/boot) directory.
      '';
    };

    postBuildCommands = mkOption {
      example = literalExpression "'' dd if=\${pkgs.myBootLoader}/SPL of=$img bs=1024 seek=1 conv=notrunc ''";
      default = "";
      description = lib.mdDoc ''
        Shell commands to run after the image is built.
        Can be used for boards requiring to dd u-boot SPL before actual partitions.
      '';
    };

    compressImage = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc ''
        Whether the SD image should be compressed using
        {command}`zstd`.
      '';
    };

    expandOnBoot = mkOption {
      type = types.bool;
      default = true;
      description = lib.mdDoc ''
        Whether to configure the sd image to expand it's partition on boot.
      '';
    };
  };

  config = {
    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/NIXOS_SD";
        fsType = "ext4";
      };
    };

    sdImage.storePaths = [ config.system.build.toplevel ];

    system.build.sdImage = pkgs.callPackage ({ stdenv, dosfstools, e2fsprogs,
    mtools, libfaketime, util-linux, zstd }: stdenv.mkDerivation {
      name = config.sdImage.imageName;

      nativeBuildInputs = [ dosfstools e2fsprogs libfaketime mtools util-linux ]
      ++ lib.optional config.sdImage.compressImage zstd;

      inherit (config.sdImage) imageName compressImage;

      buildCommand = ''
        mkdir -p $out/nix-support $out/sd-image
        export img=$out/sd-image/${config.sdImage.imageName}

        echo "${pkgs.stdenv.buildPlatform.system}" > $out/nix-support/system
        if test -n "$compressImage"; then
          echo "file sd-image $img.zst" >> $out/nix-support/hydra-build-products
        else
          echo "file sd-image $img" >> $out/nix-support/hydra-build-products
        fi

        root_fs=${rootfsImage}
        ${lib.optionalString config.sdImage.compressImage ''
        root_fs=./root-fs.img
        echo "Decompressing rootfs image"
        zstd -d --no-progress "${rootfsImage}" -o $root_fs
        ''}

        # Gap in front of the first partition, in MiB
        gap=${toString config.sdImage.firmwarePartitionOffset}

        # Create the image file sized to fit /boot/firmware and /, plus slack for the gap.
        rootSizeBlocks=$(du -B 512 --apparent-size $root_fs | awk '{ print $1 }')
        firmwareSizeBlocks=$((${toString config.sdImage.firmwareSize} * 1024 * 1024 / 512))
        imageSize=$((rootSizeBlocks * 512 + firmwareSizeBlocks * 512 + gap * 1024 * 1024))
        truncate -s $imageSize $img

        # type=a2 is 'altera boot', type=83 is 'Linux'.
        # The "bootable" partition is where u-boot will look file for the bootloader
        # information (dtbs, extlinux.conf file).
        sfdisk $img <<EOF
            label: dos
            label-id: ${config.sdImage.firmwarePartitionID}

            start=''${gap}M, size=$firmwareSizeBlocks, type=a2
            start=$((gap + ${toString config.sdImage.firmwareSize}))M, type=83, bootable
        EOF

        # Copy the rootfs into the SD image
        eval $(partx $img -o START,SECTORS --nr 2 --pairs)
        dd conv=notrunc if=$root_fs of=$img seek=$START count=$SECTORS

        # Copy the raw bootloader image to the SD card
        eval $(partx $img -o START,SECTORS --nr 1 --pairs)
        dd conv=notrunc if=${config.sdImage.bootloaderSpl} of=$img seek=$START count=$SECTORS

        ${config.sdImage.postBuildCommands}

        if test -n "$compressImage"; then
            zstd -T$NIX_BUILD_CORES --rm $img
        fi
      '';
    }) {};

    boot.postBootCommands = lib.mkIf config.sdImage.expandOnBoot ''
      # On the first boot do some maintenance tasks
      if [ -f /nix-path-registration ]; then
        set -euo pipefail
        set -x
        # Figure out device names for the boot device and root filesystem.
        rootPart=$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /)
        bootDevice=$(lsblk -npo PKNAME $rootPart)
        partNum=$(lsblk -npo MAJ:MIN $rootPart | ${pkgs.gawk}/bin/awk -F: '{print $2}')

        # Resize the root partition and the filesystem to fit the disk
        echo ",+," | sfdisk -N$partNum --no-reread $bootDevice
        ${pkgs.parted}/bin/partprobe
        ${pkgs.e2fsprogs}/bin/resize2fs $rootPart

        # Register the contents of the initial Nix store
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration

        # nixos-rebuild also requires a "system" profile and an /etc/NIXOS tag.
        touch /etc/NIXOS
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system

        # Prevents this from running on later boots.
        rm -f /nix-path-registration
      fi
    '';
  };
}
