# NixOS for the Terasic DE1-SoC Cyclone V dev board

## Why?

I don't want to learn Yocto, and it seems like Nix is the easy way to build a
custom Linux image with patches.

## What is going on here?

This is lightly based off of the [Cyclone V SoC
GSRD](https://www.rocketboards.org/foswiki/Documentation/CycloneVSoCGSRD),
which describes how to build an image for a different board. I acquired that
image and put it on my board and it didn't output anything on serial (dammit),
so I realized I was in for just doing the whole thing myself, not that I
expected better.

The images available from the board vendor Terasic are ancient (Ubuntu 16.04 is
the latest), so they are not worth using. Thus, I am here porting a different
distro because it's the same amount of work and more reusable than doing it
with Yocto.

## Boot process

Resources:
* https://www.rocketboards.org/foswiki/Documentation/BuildingBootloaderCycloneVAndArria10

In the configuration used here (see Cyclone V Hard Processor System
Technical Reference Manual, version 20.1 page A-13 to A-14), the boot process
is using the MBR mode.

The boot ROM will find a partition of type 0xA2, which it will load 64kb of
into memory (the tiny OCRAM, not DDR3) and jump to. There are four copies of
the second phase loader/"preloader" (U-Boot SPL) in this partition.

U-Boot SPL will configure various devices, initialize the SDRAM and then start
U-Boot, which is also on the same partition. U-Boot will then load the Linux
kernel image and initrd off the root disk using the extlinux mechanism.

> **Note**: Currently I use the device tree from U-Boot which will continue
> into Linux. This is subject to revision, since it seems annoying to put that
> into the bootloader partition that won't get updated with the NixOS system.

This is all built out using a patched version of sd-image.nix from nixpkgs.
My patches make a SD image for the device in one shot, rather than requiring
later modification to add the bootloader.

## Patches

### Linux

I patched the use of a function that was removed in 2019, leading to
linux-socfpga just not building on socfpga_defconfig. I have no idea what is
the deal there so I just fixed it.

The kconfig here is the socfpga_defconfig plus some entries required by
systemd/NixOS. It's pretty minimal.

You can hack on the kconfig with (FIXME probably shouldn't use qt5.full but
it's the one that was most obvious):

```
[acquire linux-socfpga]

$ nix-shell -p pkgsCross.armv7l-hf-multiplatform.stdenv.cc stdenv gmp mpfr libmpc ncurses qt5.full --run zsh
$ make socfpga_defconfig ARCH=arm CROSS_COMPILE="armv7l-unknown-linux-gnueabihf-"
$ make xconfig ARCH=arm CROSS_COMPILE="armv7l-unknown-linux-gnueabihf-"
```

### U-Boot

There are two critical bugs I patched in the device tree shipped by U-Boot for
DE1-SoC that render the system unusable:

* The frequency of the UART device is unspecified, which means that even the
  SPL can't output anything on serial. I found this in a forum post from
  mid-2021.
* The watchdog0 is marked "disabled" in the u-boot device tree for the
  DE1-SoC. This was done by upstream since it *should* probably be marked
  disabled for U-Boot, but Linux *needs* to enable it, and so the system would
  reboot due to watchdog after 10 seconds or so.

  This is not the best way to fix this, and it is likely that we will start
  using device trees shipped by NixOS instead.

## Usage

### Known bugs

* Currently U-Boot reports that its environment file is corrupt. I assume I'm
  doing something wrong, but this means that getting the system to boot
  involves typing `run bootcmd_mmc0` at the U-Boot prompt manually, at the
  moment.

  This will be fixed Eventually, but this needs to ship for a class project
  promptly and I don't have time right now. I wouldn't mind a PR fixing it but
  I will fix this eventually.
* I haven't done anything about the fact that the Nix setup is kinda hardcoded
  to x86_64-linux right now. Just patch it if you are building from a more fun
  architecture.

### Program to SD

```
$ nix build .#sdImage
$ sudo dd of=/dev/YOUR_SD_CARD_PROBABLY_mmcblk0 if=result/sd-image/nixos-*.img bs=1M status=progress
```

### Connect to serial

Attach your computer to the *mini USB* on the board (*not* the USB type B; that
one is JTAG).

```
$ picocom -q -b 115200 /dev/ttyUSB0
```

### It works!

```
U-Boot SPL 2022.04 (Jan 01 1980 - 00:00:00 +0000)
Trying to boot from MMC1


U-Boot 2022.04 (Jan 01 1980 - 00:00:00 +0000)

CPU:   Altera SoCFPGA Platform
FPGA:  Altera Cyclone V, SE/A5 or SX/C5 or ST/D5, version 0x0
BOOT:  SD/MMC Internal Transceiver (3.0V)
       Watchdog enabled
DRAM:  1 GiB
Core:  21 devices, 12 uclasses, devicetree: separate
MMC:   dwmmc0@ff704000: 0
Loading Environment from MMC... *** Warning - bad CRC, using default environment

In:    serial
Out:   serial
Err:   serial
Model: Terasic DE1-SoC
Net:
Error: ethernet@ff702000 address not set.
No ethernet found.

=>
=> run bootcmd_mmc0
switch to partitions #0, OK
mmc0 is current device
Scanning mmc 0:2...
Found /boot/extlinux/extlinux.conf
Retrieving file: /boot/extlinux/extlinux.conf
1:	NixOS - Default
Retrieving file: /boot/extlinux/../nixos/666zyfzbbm1pmnpx25pjvbp6blaw240w-initrd-linux-armv7l-unknown-linux-gnueabihf-5.15.50-initrd
Retrieving file: /boot/extlinux/../nixos/i0q6qrpxn6s9niw07zl12xiklnb82q6y-linux-armv7l-unknown-linux-gnueabihf-5.15.50-zImage
append: init=/nix/store/4l6xz4cqhk4wyamlipvhw2gz5kzrj8h1-nixos-system-nixos-23.05.20230131.e1e1b19/init console=ttyS0,115200n8 loglevel=7
Kernel image @ 0x1000000 [ 0x000000 - 0x56d200 ]
## Flattened Device Tree blob at 3bf90630
   Booting using the fdt blob at 0x3bf90630
   Loading Ramdisk to 0978f000, end 09fffa07 ... OK
   Loading Device Tree to 09787000, end 0978e88f ... OK

Starting kernel ...

Deasserting all peripheral resets
[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 5.15.50 (nixbld@localhost) (armv7l-unknown-linux-gnueabihf-gcc (GCC) 11.3.0, GNU ld (GNU Binutils) 2.39) #1-NixOS SMP Tue Jan 1 00:00:00 UTC 1980
[    0.000000] CPU: ARMv7 Processor [413fc090] revision 0 (ARMv7), cr=10c5387d
[    0.000000] CPU: PIPT / VIPT nonaliasing data cache, VIPT aliasing instruction cache
[    0.000000] OF: fdt: Machine model: Terasic DE1-SoC
[    0.000000] Memory policy: Data cache writealloc
[    0.000000] efi: UEFI not found.
```

