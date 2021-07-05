#!/bin/bash
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
PAYLOAD=$4
FPGA_HANDOFF_DIR=hps_isw_handoff
FPGA_BITFILE_RBF=$FPGA_DIR/output_files/$FPGA_PROJECT-hps.core.rbf
UBOOT_DIR=u-boot-socfpga
UBOOT_BIN=spl/u-boot-spl-dtb.ihex
LINUX_DIR=linux-socfpga
SD_IMAGE=sdimage.img
ROOT_SIZE_MIB=3270
SD_SIZE_MIB=3810
shift
shift
shift
shift
# parameters 5 and later
PACKAGES="$@"

DTB=socfpga_stratix10_de10_pro.dtb

SCRIPT_NAME=$(readlink -f "$0")
SCRIPT_PATH=$(dirname "$SCRIPT_NAME")

function ubuntu() {
	BOOT=mnt/1
	ROOT=mnt/2
	echo "fetch_ubuntu"
	$SCRIPT_PATH/fetch_ubuntu.sh
	echo "configure_system"
	$SCRIPT_PATH/configure_system.sh $ROOT/
	echo "configure_networking"
	$SCRIPT_PATH/configure_networking.sh $ROOT/
	echo "ubuntu_packages"
	$SCRIPT_PATH/ubuntu_packages.sh $ROOT/ $PACKAGES
	if [ -n "$PAYLOAD" ] ; then
		echo "Copying extra files into tree"
		sudo cp -av $PAYLOAD/* $ROOT/
	fi
	echo "Copying cloud_init files"
	cp -a $BOOT/meta-data .
	cp -a $BOOT/user-data .
	cp -a $BOOT/network-config .
}


function kernel() {
	echo "build_linux"
	$SCRIPT_PATH/build_linux.sh
}

function uboot() {
	echo "make_uboot"
	$SCRIPT_PATH/build_uboot.sh $FPGA_DIR/$FPGA_HANDOFF_DIR
	cp $UBOOT_DIR/u-boot.img .
	cp $SCRIPT_PATH/u-boot.txt .
	$UBOOT_DIR/tools/mkimage -A arm -T script -O linux -d u-boot.txt u-boot.scr
}

function devicetree() {
#	$SCRIPT_PATH/make_device_tree.sh $FPGA_DIR $QSYS.sopcinfo
#	cp -a $FPGA_DIR/$DTB $DTB	
	echo "make_device_tree"
	cp $LINUX_DIR/arch/arm64/boot/dts/altera/$DTB .
}

function bitfile() {
	$SCRIPT_PATH/make_bitfile.sh $FPGA_DIR $FPGA_PROJECT $UBOOT_DIR/$UBOOT_BIN
	cp -a $FPGA_BITFILE_RBF socfpga.core.rbf
}

function sdimage() {
	CLOUD_INIT="meta-data,user-data,network-config"
	echo "Building SD card image"
	sudo rm -f $SD_IMAGE
	sudo $SCRIPT_PATH/make_sdimage.py -f	\
		-P mnt/2/*,num=2,format=ext3,size=${ROOT_SIZE_MIB}M,label=cloudimg-rootfs \
		-P Image,${DTB},u-boot.img,u-boot.scr,socfpga.core.rbf,$CLOUD_INIT,num=1,format=vfat,size=500M,label=system-boot \
		-s ${SD_SIZE_MIB}M \
		-n $SD_IMAGE
}


function tidy() {
	sudo umount mnt/1 mnt/2
}


ubuntu && \
kernel && \
uboot && \
devicetree && \
bitfile && \
sdimage && \
tidy
