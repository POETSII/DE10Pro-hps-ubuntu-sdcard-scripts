# Ubuntu SD card building scripts for ARM CPU on Arria 10 SoC FPGAs

These scripts will build SD cards to boot Ubuntu on the hard ARM cores on
Intel Arria 10 FPGAs.  As well as the SD card image, they will build kernel, u-boot
and device tree pieces, as well as downloading a pre-built FPGA bitfile at
boot time.  Ubuntu and compiler images are downloaded as part of the build
process.

## Prerequisites

* A Linux machine with the Quartus tools installed and on your PATH (tested with Ubuntu 16.04/18.04 and Quartus
  18.1).  In particular, the 'Intel SoC FPGA Embedded Development Suite Standard
  Edition'.  A licence for Quartus should not be necessary if you are not
  resynthesising the FPGA bitfiles.
* A Quartus project which has built a suitable bitfile (.sof) - this will be converted to the necessary .rbf as part of the build
* A Platform Designer (Qsys) design of the FPGA SoC that will be used to build the device tree
* An internet connection (to download necessary pieces)
* sudo access (since building SD card images requires the loopback device)

## Usage

./build_ubuntu_sdcard.sh \<path to FPGA project directory\> \<name of Quartus project\> \<name of Qsys project> \<folder with extra files to add to tree>

## Author

Theo Markettos

thunderclap+atm26 at cl.cam.ac.uk
