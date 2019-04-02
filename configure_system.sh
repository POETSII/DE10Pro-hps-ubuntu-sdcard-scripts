#!/bin/sh
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

INSTALL=$1

# set fstab to reflect actual hardware
# (since image builder script can't set disc labels itself)
FSTAB=$INSTALL/etc/fstab
sudo sed -i "s%LABEL=cloudimg-rootfs%/dev/mmcblk0p2%g" $FSTAB
sudo sed -i "s%LABEL=system-boot%/dev/mmcblk0p1%g" $FSTAB
sudo sed -i "s%/firmware%%g" $FSTAB

# add a helpful message so user knows how to login on the terminal
ISSUE=$INSTALL/etc/issue
echo "First login username 'ubuntu', password 'ubuntu', sudo available" | sudo tee -a $ISSUE
echo "" | sudo tee -a $ISSUE

# change the hostname to something more descriptive
echo "arria10" | sudo tee $INSTALL/etc/hostname
# prevent sudo from complaining
echo "127.0.1.1    arria10" | sudo tee -a $INSTALL/etc/hosts
