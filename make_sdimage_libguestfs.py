#!/usr/bin/env python
#
# Copyright (c) 2014, Altera Corporation
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of Altera Corporation nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED.  IN NO EVENT SHALL ALTERA CORPORATION BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import os
import sys
import re
import glob
import argparse
import textwrap
import subprocess
import time
import guestfs

MAX_PARTITIONS = 4

# Globals
loopback_dev_used = []
mounted_fs = []

guest = guestfs.GuestFS(python_return_dict=True)
guest.set_trace(1)
guest_disk = []
guest_parts = []

#
#  ######  #    #  #    #   ####    ####
#  #       #    #  ##   #  #    #  #
#  #####   #    #  # #  #  #        ####
#  #       #    #  #  # #  #            #
#  #       #    #  #   ##  #    #  #    #
#  #        ####   #    #   ####    ####
#

def check_output(*popenargs, **kwargs):
    r"""Run command with arguments and return its output as a byte string.

    Backported from Python 2.7 as it's implemented as pure python on stdlib.

    >>> check_output(['/usr/bin/python', '--version'])
    Python 2.6.2
    """
    process = subprocess.Popen(stdout=subprocess.PIPE, *popenargs, **kwargs)
    output, unused_err = process.communicate()
    retcode = process.poll()
    if retcode:
        cmd = kwargs.get("args")
        if cmd is None:
            cmd = popenargs[0]
            error = subprocess.CalledProcessError(retcode, cmd)
            error.output = output
        raise error
    return output

#==============================================================================
# Convert to bytes
def convert_size_from_unit(unit_size):

    factor = 1

    m = re.match("^[0-9]+[KMG]?$", unit_size, re.I)
    if m == None:
        print "error: "+unit_size+": malformed expression"
        sys.exit(-1)
    else:
        munit = re.search("[KMG]+$", m.group(0), re.I)
        msize = re.search("^[0-9]+", m.group(0), re.I)

        if munit :
            unit = munit.group(0).upper()

            if unit == 'K':
                factor = 1024
            elif unit == 'M':
                factor = 1024*1024
            elif unit == 'G':
                factor = 1024*1024*1024

    # convert_str_to_int() takes care of handling exceptions
    size = convert_str_to_int(msize.group(0))*factor

    return size

#==============================================================================
# converts a string to int, with exception handling
def convert_str_to_int(string):

    try:
        integer = int(string)

    except ValueError:
        print "error: "+string+": not a valid number"
        sys.exit(-1)

    return integer

#==============================================================================
# Checks the requested file system format is supported
def validate_format(fs_format):

    match = re.search("^(ext[2-4]|xfs|fat32|vfat|fat|none|raw)$", fs_format, re.I)
    if match:
        return True
    else:
        return False

#==============================================================================
# The switch '-P' can be used multiple times, this function checks one
# instance
# It returns a dictionary with the right entries
def parse_single_part_args(part):

    part_entries = {}
    part_entries['files'] = []

    p = re.compile("[a-zA-Z0-9]+=")

    for el in part.split(","):
        if p.match(el):
            key, value = el.split("=")
            #  need to test for a situation like key=, that is
            #! without a value.
            if value == None:
                print "error: "+key+": no value found."
                sys.exit(-1)

            # check that a valid key was used
            if key == 'num':
                part_entries[key] = convert_str_to_int(value)
            elif key == 'size':
                size = convert_size_from_unit(value)
                part_entries[key] = size
            elif key == 'format':
                if validate_format(value):
                    part_entries[key] = value
                else:
                    print "error:", value, "unknown format"
                    sys.exit(-1)
            elif key == 'type':
                part_entries[key] = value
            else:
                print "error:", key,": unknown option"
                sys.exit(-1)
        else:
            part_entries['files'].append(el)

    return part_entries

#==============================================================================
# Parse all the arguments provided with all the '-P' switches
def parse_all_parts_args(part_args):

    part_entries = {}

    num_args = len(part_args)
    if num_args > MAX_PARTITIONS:
        print "error: up to "+str(MAX_PARTITIONS)+" allowed"
        sys.exit(-1)

    for part in part_args:
        part_entry = parse_single_part_args(part)
        if part_entry['num'] in part_entries.keys():
            print "error:"+str(part_entry['num'])+": partition already used"
            sys.exit(-1)

        part_entries[part_entry['num']] = part_entry

    return part_entries

#==============================================================================
# in some cases, a partition type (fdisk) can be inferred from the file system
# format, e.g. ext[2-4], type=83
def derive_fdisk_type_from_format(pformat):

    ptype = ""

    if re.match('^ext[2-4]|xfs$', pformat):
        ptype = '83'
    elif re.match('^vfat|fat|fat32$', pformat):
        ptype = 'b'
    else:
        print "error:", pformat,": unknown format"
        sys.exit(-1)

    return ptype

#==============================================================================
# The partition type provided by the user is not in the format that fdisk
# expects. This function translates to fdisk type defs
def derive_fdisk_type_from_ptype(ptype):

    ptype = ""

    if re.match('^raw|none$', ptype):
        fdisk_type = 'A2'
    elif ptype == 'swap':
        fdisk_type = '84'
    else:
        print "error:", ptype,": unknown type"
        sys.exit(-1)

    return fdisk_type

#==============================================================================
# This function checks the partition definitions and calculates the
# partition offsets
def check_and_update_part_entries(part_entries, image_size):

    entry = {}
    offset = 2048   # in blocks of 512 bytes
    total_size = 0


    for part in part_entries.keys():

        entry = part_entries[part]

        # we need to check if num, size and format are set
        # if type is not set but format is set, we can derive the type
        # as long as the format is not 'raw' or 'none'
        if 'size' not in entry:
            print "error:", part, ": size must be specified"
            sys.exit(-1)
        if entry['size'] == 0:
            print "error:", part, ": size is 0"
            sys.exit(-1)
        total_size = total_size + entry['size']

        if 'format' not in entry:
            if 'type' not in entry:
                print "error:", part,": specify at least format or type"
                sys.exit(-1)

            part_entries[part]['fdisk_type'] = derive_fdisk_type_from_ptype(entry['type'])

        else: # format in  entry
            if 'type' not in entry:
                part_entries[part]['fdisk_type'] = derive_fdisk_type_from_format(entry['format'])
            else:
                part_entries[part]['fdisk_type'] = entry['type']

        # update offset
        part_entries[part]['start'] = offset # in sectors
        bsize = ( entry['size'] / 512 + ((entry['size'] % 512) != 0)*1)  # because size is in bytes
        offset = offset + bsize + 1

        # it is handy to save the size in blocks, as this is what fdisk needs
        part_entries[part]['bsize'] = bsize

    if total_size > image_size:
        print "error: partitions are too big to fit in image"
        sys.exit(-1)

    return part_entries

#==============================================================================
# this script can only be run by the zuper user
def is_user_root():
    return True

#==============================================================================
# check if a file exists
def check_file_exists(filename):

    return os.path.isfile(filename)

#==============================================================================
# this function creates an empty image
def create_empty_image(image_name, image_size, force_erase_image):

    # first check if the image exists...
    if check_file_exists(image_name):
        if force_erase_image == False:
            yes_or_no = raw_input("the image "+image_name+" exists. Remove? [y|n] ")
        else:
            yes_or_no = 'Y'

        if yes_or_no == 'Y' or yes_or_no == 'y':
            try:
                os.remove(image_name)
            except OSError:
                print "error: failed to remove "+image_name+". Exit"
                sys.exit(-1)
            print "image removed"

        else:
            print "user declined"
            return False

    # now we can proceed with the image creation
    # we'll create an empty image to speed things up...
    try:
        global guest_disk
        guest.disk_create(image_name, format="raw", size=image_size)
        guest.add_drive_opts(image_name, format="raw", readonly=0)
        guest.launch()
        devices = guest.list_devices ()
        assert (len (devices) == 1)
        guest_disk = devices[0]
        print(guest_disk)
    
    except subprocess.CalledProcessError:
        print "error: failed to create the image"
        sys.exit(-1)

    return True

#==============================================================================
# this function creates a loopback device
# it is assumed the file exists
# offset in bytes
def create_loopback(image_name, size, offset=0):
    return image_name

#==============================================================================
# this function deletes a loopback device
def delete_loopback(device):
    return True

#==============================================================================
# clean up
def clean_up():

    for mp in mounted_fs:
        umount_fs(mp)

    for device in loopback_dev_used:
        if not delete_loopback(device):
            print "error: could not delete loopback device", device


    return 0

#==============================================================================
# this function creates the partition table
def create_partition_table(loopback, partition_entries):

    # our command list for fdisk
    cmd = ""
    # the number of questions asked bby fdisk, for one partition depebds
    #!on the number of partitions defined
    first_part = True


    print(partition_entries)
    assert(guest_disk != [])
    guest.part_init(guest_disk,'msdos')


    i = 1
    for part in partition_entries.keys():
        pentry = partition_entries[part]
        print(pentry)
        num = pentry['num']
        assert(num==i)
        start = pentry['start']
        size = pentry['size']
        type = int(pentry['fdisk_type'], 16)
        guest.part_add(guest_disk, prlogex='p', startsect=start, endsect=start+size/512)
        guest.part_set_mbr_id(guest_disk, num, type)==0
        i = i + 1
    return

#==============================================================================
# map format to a command
def get_mkfs_from_format(pformat):

    cmd = ""

    if re.search("^ext[2-4]$", pformat):
        cmd = "mkfs."+pformat
    elif re.search("fat|vfat|fat32", pformat):
        cmd = "mkfs.vfat"
    elif re.search("^xfs$", pformat):
        cmd = "mkfs.xfs"

    return cmd

#==============================================================================
# map format to a command parameter
def get_mkfs_params_from_format(pformat):

    params = ""

    if re.search("fat32", pformat):
        params = "-F 32"

    return params

#==============================================================================
# formats a vlock device
def format_partition(loopback, fs_format):

    cmd = get_mkfs_from_format(fs_format)
    params = get_mkfs_params_from_format(fs_format)
    print(fs_format)

    if fs_format != 'raw':
        guest.mkfs(fs_format, loopback)

    return

def get_mountfs_from_format(pformat):
    format = pformat

    if re.search("fat32|fat", pformat):
        format = "vfat"

    return format
#==============================================================================
# mount a file system
#! returns the mnt point
def mount_fs(loopback, fs_format):

    mp = "/"
    guest.mount_options("", loopback, mp)
    return mp


    mp = "/tmp/"+str(int(time.time()))+"_"+str(os.getpid())
    try:
        os.mkdir(mp)
    except OSError:
        print "error: failed to create mount point (", mp,")"
        clean_up()
        sys.exit(-1)

    format = get_mountfs_from_format(fs_format)

    p = subprocess.Popen(["mount", "-t", format, loopback, mp],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    p.wait()
    if p.returncode != 0:
        print "error: mount: failed (", loopback, mp,")"
        clean_up()
        sys.exit(-1)

    # keep track of the mount points
    mounted_fs.append(mp)

    return mp

#==============================================================================
# unmount fs
def umount_fs(mp):

    time.sleep(3)
    p = subprocess.Popen(["umount", mp],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    p.wait()
    if p.returncode != 0:
        print "error: failed to umount", mp
        sys.exit(-1)

    # update the list
    mounted_fs.remove(mp)

    return

#==============================================================================
#do a raw copy of files to a partition
def do_raw_copy(loopback, partition_data):

    offset = 0  # offset in bytes

    # below, stuff is just a file...
    for stuff in partition_data['files']:
        # we do accept FILES only, no directories please
        if os.path.isdir(stuff):
            print "error:", stuff, ": can't copy dirs to raw partitions"
            clean_up()
            sys.exit(-1)

        assert(offset==0) # currently can't cope with appending
        # 'upload' direct to the block device, ie operate as dd
        guest.upload(stuff, loopback)
        # this assumes it's already inside the VM
#        guest.copy_device_to_device("/upload", loopback, destoffset=offset)
        

        # now dd the file:
        #! dd if=file of=loopback bs=1 seek=offset
#        p = subprocess.Popen(["dd", "if="+stuff, "of="+loopback, "bs=1",
#                             "seek="+str(offset)],
#                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
#        p.wait()
#        if p.returncode != 0:
#            print "error:", stuff, ": failed to do raw copy"
#            clean_up()
#            sys.exit(-1)

        # handle offset
        offset = offset + os.stat(stuff).st_size

    return

#==============================================================================
# copy files over a file system
def do_copy(loopback, partition_data):
    print("do_copy not implemented")
#    return

    mp = mount_fs(loopback, partition_data['format'])
    for stuff in partition_data['files']:
        if os.path.isdir(stuff):
            stuff = stuff+"/*"

        # some file systems have limited flags like FAT
        if re.search("^fat|vfat|fat32$", partition_data['format']):
            cp_opt = "-rt"
        else:
            cp_opt = "-at"

        # as we need to do UNIX path expansion, we'll use the class glob,
        #! so we need to call cp with the option -t, such that the destination
        #! directory can be specified first. The list returned by glob can then
        #! be added to the list of args passed to Popen
        print mp
        files = glob.glob(stuff)
        print(files)
        
        for file in files:
            guest.upload(file, mp+"/"+stuff)


#        try:
#            p = subprocess.Popen(["cp", cp_opt, mp ] + glob.glob(stuff),
#                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
#            [output,stderr] = p.communicate()
#            if p.returncode:
#                raise Exception([])
#        except Exception:
#            print "error: failed to copy", stuff
#            clean_up()
#            sys.exit(-1)
#
#    umount_fs(mp)

    return

#==============================================================================
# copy files to  a partition
#! takes care of the format, if raw|none use dd
def copy_files_to_partition(loopback, partition_data):

    if re.search("raw|none", partition_data['format']):
        # RAW patition, nothin to mount, the files must be
        #! dd'ed in. ONLY files allowed, no directory
        # if multiple files are provided, they are dd'ed one after another,
        #! no GAP. If not acceptable, one file should be passed, as an image
        do_raw_copy(loopback, partition_data)
    else:
        do_copy(loopback, partition_data)

    return

#==============================================================================
# create, formats and copt files to partition
def do_partition(partition, image_name):

    offset_bytes = partition['start'] * 512

    if partition['format'] == "fat32" and partition['size'] < 33554432:
        print "error: Unable to create a fat32 partition size < 32MB"
        sys.exit(-1)

#    loopback = create_loopback(image_name, partition['size'], offset_bytes)
    loopback = image_name
    print(loopback)
    format_partition(loopback, partition['format'])
    copy_files_to_partition(loopback, partition)
    time.sleep(3)
    if not delete_loopback(loopback):
        clean_up()
        sys.exit(-1)

    return

#==============================================================================
def create_image(image_name, image_size, partition_entries, force_erase_image):

    print "info: creating the image "+image_name
    # first we need an empty image
    if not create_empty_image(image_name, image_size, force_erase_image):
        print "error: the image file could not be created"
        sys.exit(-1)

    # second, we'll create the partition table
    print "info: creating the partition table"
    loopback = create_loopback(image_name, image_size)
    create_partition_table(loopback, partition_entries)
    delete_loopback(loopback)

    # now we iterate over the partitions
    print "info: processing partitions..."
    guest_parts = guest.list_partitions()
    print(guest_parts)
    for part in partition_entries.keys():
        print "     partition #"+str(part)+"..."
        do_partition(partition_entries[part], guest_parts[part-1])

    return

#==============================================================================
#==============================================================================
#
#   ####    #####    ##    #####    #####
#  #          #     #  #   #    #     #
#   ####      #    #    #  #    #     #
#       #     #    ######  #####      #
#  #    #     #    #    #  #   #      #
#   ####      #    #    #  #    #     #
#
part_entries = []

# arguments
parser = argparse.ArgumentParser(description='Creates an SD card image for Altera\'s SoCFPGA SoC\'s',
                                 epilog = textwrap.dedent('''\
Usage: PROG [-h] -P <partition info> [-P ...]
-P
'''
))
parser.add_argument('-P', dest='part_args', action='append',
                    help='''specifies a partition. May be used multiple times.
                            file[,file,...],num=<part_num>,format=<vfat|fat32|ext[2-4]|xfs|raw>,
                            size=<num[K|M|G]>[,type=ID]''')
parser.add_argument('-s', dest='size', action='store',
                    default='8G', help='specifies the size of the image. Units K|M|G can be used.')
parser.add_argument('-n', dest='image_name', action='store',
                    default='somename.img', help='specifies the name of the image.')
parser.add_argument('-f', dest='force_erase_image', action='store_true',
                    default=False, help='deletes the image file if exists')
args = parser.parse_args()

# Only root can do this
if not is_user_root():
    print "error: only root can do this..."
    sys.exit(-1)

# A few checks
part_entries = parse_all_parts_args(args.part_args)
image_size = convert_size_from_unit(args.size)
part_entries = check_and_update_part_entries(part_entries, image_size)
print(part_entries)

# we now have what we need
create_image(args.image_name, image_size, part_entries, args.force_erase_image)
print "info: image created, file name is ", args.image_name

