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

COMPILER_FILE="gcc-linaro-7.2.1-2017.11-x86_64_aarch64-linux-gnu"
COMPILER_URL="https://releases.linaro.org/components/toolchain/binaries/7.2-2017.11/aarch64-linux-gnu/${COMPILER_FILE}.tar.xz" 
CWD=$(pwd)
CPUS=8

KERNEL_BRANCH="de10_pro_revC"

echo "Fetching compiler..."
wget -c $COMPILER_URL
echo "Untarring compiler..."
tar xJf $COMPILER_FILE.tar.xz
export CROSS_COMPILE=$CWD/$COMPILER_FILE/bin/aarch64-linux-gnu-

if [ -d linux-socfpga ] ; then
	echo "Cleaning and updating to upstream Linux source..."
	cd linux-socfpga
	git fetch origin
	# may not want this if there are local modifications in-tree
	git reset --hard origin/$KERNEL_BRANCH
else
	echo "Fetching Linux source..."
	git clone https://github.com/terasic/linux-socfpga
	cd linux-socfpga
	git checkout $KERNEL_BRANCH
fi


export ARCH=arm64
echo "Configuring Linux source..."
if [ -f .config ] ; then
	echo "Using existing kernel configuration .config"
else
	echo "Creating new configuration from supplied de10_pro.config"
	cp -a de10_pro.config .config
fi
# may need to install ncurses-devel or ncurses-dev package for this step
#  may also need to install flex, bison
#make defconfig
# change any options here
#make menuconfig

#echo "Edit device tree now"
#read -n1 -rsp $'Press any key to continue or Ctrl+C to exit...\n'

make all -j$CPUS
cp -a arch/arm64/boot/Image ../
