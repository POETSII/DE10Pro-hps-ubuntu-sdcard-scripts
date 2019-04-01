#!/bin/bash -e
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2018 A. Theodore Markettos
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory (Department of Computer Science and
# Technology) under DARPA contract HR0011-18-C-0016 ("ECATS"), as part of the
# DARPA SSITH research programme.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#


FPGA_DIR=$1
FPGA_PROJECT=$2
QSYS=$3
FPGA_HANDOFF_DIR=hps_isw_handoff
FPGA_BITFILE_RBF=$FPGA_DIR/output_files/$FPGA_PROJECT.rbf
SD_IMAGE=sdimage.img
ROOT_SIZE_MB=1500
SD_SIZE_MB=2048
echo $SCRIPT_PATH

DTB=socfpga_arria10_socdk_sdmmc.dtb

SCRIPT_NAME=$(readlink -f "$0")
SCRIPT_PATH=$(dirname "$SCRIPT_NAME")

function ubuntu() {
	$SCRIPT_PATH/fetch_ubuntu.sh
	$SCRIPT_PATH/configure_networking.sh mnt/2/
}

function kernel() {
	$SCRIPT_PATH/build_linux.sh
}

function uboot() {
	$SCRIPT_PATH/make_uboot.sh $FPGA_DIR/$FPGA_HANDOFF_DIR
	cp -a bsp/uboot_w_dtb-mkpimage.bin .
}

function devicetree() {
	$SCRIPT_PATH/make_device_tree.sh $FPGA_DIR $QSYS.sopcinfo

	cp -a $FPGA_DIR/$DTB $DTB	
}

function bitfile() {
#	$SCRIPT_PATH/make_bitfile.sh $FPGA_DIR $FPGA_PROJECT
	cp -a $FPGA_BITFILE_RBF socfpga.rbf
}

function sdimage() {

	echo "Building SD card image"
	sudo $SCRIPT_PATH/make_sdimage.py -f	\
		-P uboot_w_dtb-mkpimage.bin,num=3,format=raw,size=10M,type=A2 \
		-P mnt/2/*,num=2,format=ext3,size=${ROOT_SIZE_MB}M \
		-P zImage,socfpga.rbf,socfpga_arria10_socdk_sdmmc.dtb,num=1,format=vfat,size=500M \
		-s ${SD_SIZE_MB}M \
		-n $SD_IMAGE

}


function tidy() {
	sudo umount mnt/1 mnt/2
}


ubuntu
kernel
uboot
devicetree
bitfile
sdimage
tidy
