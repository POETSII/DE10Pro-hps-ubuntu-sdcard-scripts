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

UBUNTU_URL="http://cdimage.ubuntu.com/releases/18.04/release"
UBUNTU_FILE="ubuntu-18.04.2-preinstalled-server-arm64+raspi3"

# handy functions for driving losetup, based on
# https://stackoverflow.com/a/39675265

los() {
  img="$1"
  dev="$(sudo losetup --show -f -P "$img")"
  for part in "$dev"?*; do
    num=${part##${dev}p}
    dst="mnt/$num"
    echo "Found image partition $num, mounting $part at $dst"
    mkdir -p "$dst"
    sudo mount "$part" "$dst"
  done
  loopdev="$dev"
}

losd() {
  dev="$1"
  for part in "$dev"?*; do
    num=${part##${dev}p}
    dst="mnt/$num"
    echo "Found image partition $num, unmounting $part at $dst"
    sudo umount "$part" "$dst"
  done
  sudo losetup -d "$dev"
}


wget -c $UBUNTU_URL/$UBUNTU_FILE.img.xz
unxz $UBUNTU_FILE.img.xz
los $UBUNTU_FILE.img
echo $loopdev
#losd $loopdev
