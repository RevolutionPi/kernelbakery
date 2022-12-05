#!/bin/bash -e

copy_files() {
    builddir=$1
    destdir="headers/usr/src/linux-headers-$version"
    mkdir -p "$destdir"
    mkdir -p "headers/lib/modules/$version"
    rsync -aHAX \
        --files-from=<(
            cd linux
            find . -name Makefile\* -o -name Kconfig\* -o -name \*.pl | grep -E -v '^\./debian'
        ) linux/ "$destdir/"
    rsync -aHAX \
        --files-from=<(
            cd linux
            find "arch/${ARCH}/include" include scripts -type f
        ) linux/ "$destdir/"
    rsync -aHAX \
        --files-from=<(
            cd linux
            find "arch/${ARCH}" -name module.lds -o -name Kbuild.platforms -o -name Platform
        ) linux/ "$destdir/"
    rsync -aHAX \
        --files-from=<(
            cd linux
            find "arch/${ARCH}" -name include -type d -print0 -o -name scripts -type d -print0 |
                xargs -0 -I '{}' find '{}' -type f
        ) \
        linux/ \
        "$destdir/"
    rsync -aHAX \
        --files-from=<(
            cd "$builddir"
            find "arch/${ARCH}/include" Module.symvers .config include scripts -type f
        ) "$builddir" "$destdir/"
    find "$destdir/scripts" -type f -exec file {} + | grep -E 'ELF .* x86-64' | cut -d: -f1 | xargs rm
    find "$destdir/scripts" -type f -name '*.cmd' -exec rm {} +
    ln -sf "/usr/src/linux-headers-$version" "headers/lib/modules/$version/build"

    (
        cd linux
        make "${make_opts[@]}" -j"$NPROC" INSTALL_KBUILD_PATH="../$destdir" kbuild_install
    )
}

NPROC=$(nproc) || NPROC=8

if [ -z "$LINUXDIR" ]; then
    echo 1>&2 "Usage: LINUXDIR=<path> [PIKERNELMODDIR=<path>] $(basename "$0")"
    exit 1
elif [ ! -d "$LINUXDIR" ]; then
    echo 1>&2 "LINUXDIR defined as $LINUXDIR, but folder not found on disk."
    exit 1
fi

if [ -n "$PIKERNELMODDIR" ]; then
    if [ ! -d "$PIKERNELMODDIR" ]; then
        echo 1>&2 "PIKERNELMODDIR defined as $PIKERNELMODDIR, but folder not found on disk."
        exit 1
    fi
fi

ARCH=${ARCH:-arm}
case "$ARCH" in
arm)
    CROSS_COMPILE=${CROSS_COMPILE:-arm-linux-gnueabihf-}
    # CM1=6 CM3=7 CM4=7l (32 bit kernel)
    kernel_versions="6 7 7l"
    ;;
arm64)
    CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
    # CM3/CM4S/CM4=8 (64 bit kernel)
    kernel_versions="8"
    ;;
*)
    echo 1>&2 "Unsupported architecture: ${ARCH}"
    exit 1
    ;;
esac

INSTDIR=$(dirname "$0")
if [ "${INSTDIR#/}" == "$INSTDIR" ]; then INSTDIR="$PWD/$INSTDIR"; fi
INSTDIR=${INSTDIR%%/debian}
BUILDDIR_TEMPLATE=$INSTDIR/kbuild
KBUILD_BUILD_TIMESTAMP="$(dpkg-parsechangelog -STimestamp)"
export KBUILD_BUILD_TIMESTAMP
export KBUILD_BUILD_USER="support"
export KBUILD_BUILD_HOST="kunbus.com"
export ARCH
export CROSS_COMPILE
make_opts=(CFLAGS_KERNEL='-fdebug-prefix-map=$LINUXDIR=.' CFLAGS_MODULE='-fdebug-prefix-map=$LINUXDIR=.' O="$BUILDDIR_TEMPLATE")

if [ ! -L "$INSTDIR/linux" ]; then
    ln -sf "$LINUXDIR" "$INSTDIR/linux"
fi

[ -d "$INSTDIR/boot/overlays" ] || mkdir "$INSTDIR/boot/overlays"

# cleanup from previous builds
rm -rf "$INSTDIR/headers"
rm -f "$INSTDIR/boot/broadcom"/*.dtb "$INSTDIR/boot"/*.dtb "$INSTDIR/boot/overlays"/*.dtbo "$INSTDIR/boot"/kernel*.img
rm -rf modules/*

for kernel_version in $kernel_versions; do
    defconfig="revpi-v${kernel_version}_defconfig"
    test -f "linux/arch/${ARCH}/configs/$defconfig" || continue
    builddir=${BUILDDIR_TEMPLATE}${kernel_version/6/}
    make_opts[-1]="O=${builddir}"

    rm -rf "$builddir"
    mkdir "$builddir"

    # build kernel
    (
        cd linux
        make "${make_opts[@]}" $defconfig
    )
    if [ "$ARCH" == "arm64" ]; then
        (
            cd linux
            make "${make_opts[@]}" -j$NPROC Image modules 2>&1
        )
    else
        (
            cd linux
            make "${make_opts[@]}" -j$NPROC zImage modules 2>&1
        )
    fi
    version="$(cat "$builddir/include/config/kernel.release")"
    copy_files "$builddir"

    # build piKernelMod
    if [ -d "$PIKERNELMODDIR" ]; then
        cd "$PIKERNELMODDIR"
        make compiletime.h
        cd -
        (
            cd linux
            make "${make_opts[@]}" M="$PIKERNELMODDIR" modules
        )
    fi

    # install kernel

    if [ "$ARCH" == "arm64" ]; then
        # arm64 kernel is uncompressed by default, let's gzip it
        cp "$builddir/arch/${ARCH}/boot/Image" "$INSTDIR/boot/kernel8.img"
        gzip -9 "$INSTDIR/boot/kernel8.img"
        mv "$INSTDIR/boot/kernel8.img"{.gz,}
    else
        cp "$builddir/arch/${ARCH}/boot/zImage" "$INSTDIR/boot/kernel${kernel_version/6/}.img"
    fi

    # install modules
    if [ -d "$PIKERNELMODDIR" ]; then
        (
            cd linux
            make "${make_opts[@]}" -j$NPROC modules_install INSTALL_MOD_PATH="$INSTDIR/modules" M="$PIKERNELMODDIR"
        )
    fi
    (
        cd linux
        make "${make_opts[@]}" -j$NPROC modules_install INSTALL_MOD_PATH="$INSTDIR/modules"
    )
    mv "$INSTDIR/modules/lib/modules"/* "$INSTDIR/modules"
    rm -r "$INSTDIR/modules/lib"
    rm "$INSTDIR/modules"/*/{build,source}
done

# install dtbs (based on last builddir)
(
    cd linux
    make "${make_opts[@]}" -j$NPROC dtbs 2>&1
)
(
    cd linux
    make "${make_opts[@]}" -j$NPROC dtbs_install INSTALL_DTBS_PATH=/tmp/dtb.$$
)
if [ "$ARCH" == "arm64" ]; then
    mv /tmp/dtb.$$/broadcom/*.dtb "$INSTDIR/boot"
else
    mv /tmp/dtb.$$/*.dtb "$INSTDIR/boot"
fi
mv /tmp/dtb.$$/overlays/* "$INSTDIR/boot/overlays"
rmdir /tmp/dtb.$$/* /tmp/dtb.$$

[ ! -d "extra" ] && mkdir "extra"
echo "_ _ $version" >extra/uname_string

find headers -name .gitignore -delete
(
    cd debian
    ./gen_bootloader_postinst_preinst.sh
)
