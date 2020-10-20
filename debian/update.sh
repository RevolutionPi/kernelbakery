#!/bin/bash -e

copy_files (){
	destdir="headers/usr/src/linux-headers-$version"
	mkdir -p "$destdir"
	mkdir -p "headers/lib/modules/$version"
	rsync -aHAX \
		--files-from=<(cd linux; find -name Makefile\* -o -name Kconfig\* -o -name \*.pl | egrep -v '^\./debian') linux/ "$destdir/"
	rsync -aHAX \
		--files-from=<(cd linux; find arch/arm/include include scripts -type f) linux/ "$destdir/"
	rsync -aHAX \
		--files-from=<(cd linux; find arch/arm -name module.lds -o -name Kbuild.platforms -o -name Platform) linux/ "$destdir/"
	rsync -aHAX \
		--files-from=<( \
				cd linux; \
				find arch/arm -name include -type d -print0 -o -name scripts -type d -print0 | \
				xargs -0 -I '{}' find '{}' -type f \
			) \
			linux/ \
			"$destdir/"
	rsync -aHAX \
		--files-from=<(cd "$BUILDDIR"; find arch/arm/include Module.symvers .config include scripts -type f) "$BUILDDIR" "$destdir/"
	find "$destdir/scripts" -type f -exec file {} + | egrep 'ELF .* x86-64' | cut -d: -f1 | xargs rm
	find "$destdir/scripts" -type f -name '*.cmd' -exec rm {} +
	ln -sf "/usr/src/linux-headers-$version" "headers/lib/modules/$version/build"

	(cd linux; eval $make -j8 INSTALL_KBUILD_PATH="../$destdir" kbuild_install)
}

if [ -z "$LINUXDIR" -o -z "$PIKERNELMODDIR" ] ; then
    echo 1>&2 "Usage: LINUXDIR=<path> PIKERNELMODDIR=<path> $(basename "$0")"
    exit 1
fi

INSTDIR=$(dirname "$0")
if [ "${INSTDIR#/}" == "$INSTDIR" ] ; then INSTDIR="$PWD/$INSTDIR" ; fi
INSTDIR=${INSTDIR%%/debian}
BUILDDIR=$INSTDIR/kbuild
export KBUILD_BUILD_TIMESTAMP=$(date --rfc-2822)
export KBUILD_BUILD_USER="admin"
export KBUILD_BUILD_HOST="kunbus.de"
make="make CFLAGS_KERNEL='-fdebug-prefix-map=$LINUXDIR=.' CFLAGS_MODULE='-fdebug-prefix-map=$LINUXDIR=.' ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- O=$BUILDDIR"

rm -rf "$BUILDDIR"
mkdir "$BUILDDIR"
if [ ! -L "$INSTDIR/linux" ] ; then
    ln -sf "$LINUXDIR" "$INSTDIR/linux"
fi
rm -rf "$INSTDIR/headers"

# build CM1 kernel
(cd linux; eval $make revpi-v6_defconfig)
(cd linux; eval $make -j8 zImage modules dtbs 2>&1 | tee /tmp/out)
version=$(cat "$BUILDDIR/include/config/kernel.release")
[ ! -d "extra" ] && mkdir "extra"
echo "_ _ $version" > extra/uname_string
copy_files

# build CM1 piKernelMod
cd "$PIKERNELMODDIR"
make compiletime.h
cd -
(cd linux; eval $make M="$PIKERNELMODDIR" modules)

# install CM1 kernel
cp "$BUILDDIR/arch/arm/boot/zImage" "$INSTDIR/boot/kernel.img"

# install CM1 modules
rm -rf modules/*
(cd linux; eval $make -j8 modules_install INSTALL_MOD_PATH="$INSTDIR/modules" M="$PIKERNELMODDIR")
(cd linux; eval $make -j8 modules_install INSTALL_MOD_PATH="$INSTDIR/modules")
mv "$INSTDIR/modules/lib/modules"/* "$INSTDIR/modules"
rm -r "$INSTDIR/modules/lib"
rm "$INSTDIR/modules"/*/{build,source}

# install CM1 dtbs
[ -d "$INSTDIR/boot/overlays" ] || mkdir "$INSTDIR/boot/overlays"
rm -f "$INSTDIR/boot"/*.dtb "$INSTDIR/boot/overlays"/*.dtbo
(cd linux; eval $make -j8 dtbs_install INSTALL_DTBS_PATH=/tmp/dtb.$$)
mv /tmp/dtb.$$/*.dtb "$INSTDIR/boot"
mv /tmp/dtb.$$/overlays/* "$INSTDIR/boot/overlays"
rmdir /tmp/dtb.$$/overlays /tmp/dtb.$$

# build CM3 kernel
make+=7
BUILDDIR+=7
rm -rf "$BUILDDIR"
mkdir "$BUILDDIR"
(cd linux; eval $make revpi-v7_defconfig)
(cd linux; eval $make -j8 zImage modules dtbs 2>&1 | tee /tmp/out7)
version="$(cat "$BUILDDIR/include/config/kernel.release")"
copy_files

# build CM3 piKernelMod
cd "$PIKERNELMODDIR"
make compiletime.h
cd -
(cd linux; eval $make M="$PIKERNELMODDIR" modules)

# install CM3 kernel
cp "$BUILDDIR/arch/arm/boot/zImage" "$INSTDIR/boot/kernel7.img"

# install CM3 modules
(cd linux; eval $make -j8 modules_install INSTALL_MOD_PATH="$INSTDIR/modules" M="$PIKERNELMODDIR")
(cd linux; eval $make -j8 modules_install INSTALL_MOD_PATH="$INSTDIR/modules")
mv "$INSTDIR/modules/lib/modules"/* "$INSTDIR/modules"
rm -r "$INSTDIR/modules/lib"
rm "$INSTDIR/modules"/*/{build,source}

# install CM3 dtbs
(cd linux; eval $make -j8 dtbs_install INSTALL_DTBS_PATH=/tmp/dtb.$$)
mv /tmp/dtb.$$/*.dtb "$INSTDIR/boot"
mv /tmp/dtb.$$/overlays/* "$INSTDIR/boot/overlays"
rmdir /tmp/dtb.$$/overlays /tmp/dtb.$$

find headers -name .gitignore -delete
(cd debian; ./gen_bootloader_postinst_preinst.sh)
