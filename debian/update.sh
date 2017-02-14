#!/bin/bash -e

copy_files (){
destdir=headers/usr/src/linux-headers-$version
mkdir -p "$destdir"
mkdir -p headers/lib/modules/$version
rsync -aHAX \
	--files-from=<(cd linux; find -name Makefile\* -o -name Kconfig\* -o -name \*.pl | egrep -v '^\./debian') linux/ $destdir/
rsync -aHAX \
	--files-from=<(cd linux; find arch/arm/include include scripts -type f) linux/ $destdir/
rsync -aHAX \
	--files-from=<(cd linux; find arch/arm -name module.lds -o -name Kbuild.platforms -o -name Platform) linux/ $destdir/
rsync -aHAX \
	--files-from=<(cd linux; find `find arch/arm -name include -o -name scripts -type d` -type f) linux/ $destdir/
rsync -aHAX \
	--files-from=<(cd $BUILDDIR; find arch/arm/include Module.symvers .config include scripts -type f) $BUILDDIR $destdir/
find $destdir/scripts -type f | xargs file | egrep 'ELF .* x86-64' | cut -d: -f1 | xargs rm
find $destdir/scripts -type f -name '*.cmd' | xargs rm
ln -sf "/usr/src/linux-headers-$version" "headers/lib/modules/$version/build"

}

if [ -z "$LINUXDIR" -o -z "$PIKERNELMODDIR" ] ; then
    echo 1>&2 "Usage: LINUXDIR=<path> PIKERNELMODDIR=<path> `basename $0`"
    exit 1
fi

INSTDIR=`dirname $0`
if [ ${INSTDIR#/} == $INSTDIR ] ; then INSTDIR="$PWD/$INSTDIR" ; fi
INSTDIR=${INSTDIR%%/debian}
BUILDDIR=$INSTDIR/kbuild
KUNBUSOVERLAY=$INSTDIR/debian/kunbus.dts
export KBUILD_BUILD_TIMESTAMP=`date --rfc-2822`
export KBUILD_BUILD_USER="admin"
export KBUILD_BUILD_HOST="kunbus.de"
make="make CFLAGS_KERNEL=-fdebug-prefix-map=$LINUXDIR=. CFLAGS_MODULE=-fdebug-prefix-map=$LINUXDIR=. ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- CC=arm-linux-gnueabihf-gcc-6 O=$BUILDDIR"

rm -rf $BUILDDIR
mkdir $BUILDDIR
if [ \! -L $INSTDIR/linux ] ; then
    ln -sf $LINUXDIR $INSTDIR/linux
fi
rm -rf $INSTDIR/headers

# build CM1 kernel
(cd linux; eval $make bcmrpi_defconfig modules_prepare)
cat <<-EOF >> $BUILDDIR/.config
	CONFIG_PREEMPT_RT_FULL=y
	CONFIG_DEBUG_PREEMPT=n
	CONFIG_SECURITY=y
	CONFIG_SECURITY_YAMA=y # for ptrace_scope
	CONFIG_INTEGRITY=n
	CONFIG_BCM_VC_SM=n # hangs in initcall
	CONFIG_SUSPEND=y
	CONFIG_PM_WAKELOCKS=y
	CONFIG_RTC_HCTOSYS=y # sync from rtc on boot
	CONFIG_RTC_DRV_PCF2127=y
	CONFIG_I2C_BCM2708=y
EOF
(cd linux; eval $make olddefconfig)
(cd linux; eval $make -j8 zImage modules dtbs 2>&1 | tee /tmp/out)
version=`cat $BUILDDIR/include/config/kernel.release`
echo "_ _ $version" > extra/uname_string
copy_files

# build CM1 piKernelMod
cd $PIKERNELMODDIR
make compiletime.h
cd -
(cd linux; eval $make M=$PIKERNELMODDIR modules)

# install CM1 kernel
linux/scripts/mkknlimg $BUILDDIR/arch/arm/boot/zImage $INSTDIR/boot/kernel.img

# install CM1 modules
rm -rf modules/*
(cd linux; eval $make -j8 modules_install INSTALL_MOD_PATH=$INSTDIR/modules M=$PIKERNELMODDIR)
(cd linux; eval $make -j8 modules_install INSTALL_MOD_PATH=$INSTDIR/modules)
mv $INSTDIR/modules/lib/modules/* $INSTDIR/modules
rm -r $INSTDIR/modules/lib
rm $INSTDIR/modules/*/{build,source}

# install CM1 dtbs
[ -d $INSTDIR/boot/overlays ] || mkdir $INSTDIR/boot/overlays
rm -f $INSTDIR/boot/*.dtb $INSTDIR/boot/overlays/*.dtbo
(cd linux; eval $make -j8 dtbs_install INSTALL_DTBS_PATH=/tmp/dtb.$$)
mv /tmp/dtb.$$/*.dtb $INSTDIR/boot
mv /tmp/dtb.$$/overlays/* $INSTDIR/boot/overlays
rmdir /tmp/dtb.$$/overlays /tmp/dtb.$$
cp $LINUXDIR/arch/arm/boot/dts/overlays/README $INSTDIR/boot/overlays
cp $KUNBUSOVERLAY $INSTDIR/boot/overlays
dtc -I dts -O dtb $KUNBUSOVERLAY > $INSTDIR/boot/overlays/`basename $KUNBUSOVERLAY .dts`.dtbo

# build CM3 kernel
make+=7
BUILDDIR+=7
rm -rf $BUILDDIR
mkdir $BUILDDIR
(cd linux; eval $make bcm2709_defconfig modules_prepare)
cat <<-EOF >> $BUILDDIR/.config
	CONFIG_PREEMPT_RT_FULL=y
	CONFIG_DEBUG_PREEMPT=n
	CONFIG_SECURITY=y
	CONFIG_SECURITY_YAMA=y # for ptrace_scope
	CONFIG_INTEGRITY=n
	CONFIG_BCM_VC_SM=n # hangs in initcall
	CONFIG_SUSPEND=y
	CONFIG_PM_WAKELOCKS=y
	CONFIG_RTC_HCTOSYS=y # sync from rtc on boot
	CONFIG_RTC_DRV_PCF2127=y
	CONFIG_I2C_BCM2708=y
EOF
(cd linux; eval $make olddefconfig)
(cd linux; eval $make -j8 zImage modules dtbs 2>&1 | tee /tmp/out7)
version="`cat $BUILDDIR/include/config/kernel.release`"
copy_files

# build CM3 piKernelMod
cd $PIKERNELMODDIR
make compiletime.h
cd -
(cd linux; eval $make M=$PIKERNELMODDIR modules)

# install CM3 kernel
linux/scripts/mkknlimg $BUILDDIR/arch/arm/boot/zImage $INSTDIR/boot/kernel7.img

# install CM3 modules
(cd linux; eval $make -j8 modules_install INSTALL_MOD_PATH=$INSTDIR/modules M=$PIKERNELMODDIR)
(cd linux; eval $make -j8 modules_install INSTALL_MOD_PATH=$INSTDIR/modules)
mv $INSTDIR/modules/lib/modules/* $INSTDIR/modules
rm -r $INSTDIR/modules/lib
rm $INSTDIR/modules/*/{build,source}

# install CM3 dtbs
(cd linux; eval $make -j8 dtbs_install INSTALL_DTBS_PATH=/tmp/dtb.$$)
mv /tmp/dtb.$$/*.dtb $INSTDIR/boot
mv /tmp/dtb.$$/overlays/* $INSTDIR/boot/overlays
rmdir /tmp/dtb.$$/overlays /tmp/dtb.$$

find headers -name .gitignore -delete
(cd debian; ./gen_bootloader_postinst_preinst.sh)
