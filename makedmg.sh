#!/bin/bash

# DMG Creation Script
# Usage: makedmg <imagename> <imagetitle> <contentdir>
#
# Based on makedmg by Jon Cowie
#
# imagename: The output file name of the image, ie foo.dmg
# imagetitle: The title of the DMG File as displayed in OS X
# contentdir: The directory containing the content you want the DMG file to contain

if [ ! $# == 3 ]; then
    echo "Usage: $0 <imagename> <imagetitle> <contentdir>"
else
    OUTPUT=$1
    TITLE=$2
    CONTENTDIR=$3
    FILESIZE=$(du -sm "${CONTENTDIR}" | cut -f1)
    FILESIZE=$((${FILESIZE} + 5))
    USER=$(whoami)
    TMPDIR="/Volumes/$TITLE"
    CURRENT_DIR=$(dirname $0)
    cd $CURRENT_DIR
    if [ "${USER}" != "root" ]; then
        echo "$0 must be run as root!"
    else
        echo "Creating DMG File..."
        # 创建Dmg文件
        hdiutil create -megabytes $FILESIZE -fs HFS+ -volname "$TITLE" "$OUTPUT"
        echo "Mounting DMG File..."
        # 挂载dmg文件 - 即和打开一样
        hdiutil mount "$CURRENT_DIR/$OUTPUT.dmg"
        
        echo "Copying content to DMG File..."
        cp -R "${CONTENTDIR}"/* "${TMPDIR}"

        echo "Unmounting DMG File..."
        # 推出磁盘
        hdiutil eject "${TMPDIR}"

        echo "All Done!"
    fi
fi