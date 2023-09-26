# Revolution Pi Kernelbakery

This is a fork of the repository used by the Foundation to build kernel and
firmware packages for the Raspberry Pi: https://github.com/RPi-Distro/firmware

We use it to build kernels for the Revolution Pi and are providing it here
as a service to our users to allow building custom kernels. The resulting
deb packages serve as drop-in replacements for the Foundation's packages.
Installation with deb packages is cleaner than just copying the kernel and
modules to the bare filesystem.

Unfortunately the Foundation's repo is huge (currently 5 GByte) as it includes
all their kernels and modules in binary form dating back to 2012. That's why
this repo was stripped of the git history as well as files which can be rebuilt
from the kernel source tree.

# Intended usage

This procedure was tested successfully on Debian buster amd64, but YMMV.
Building the kernel with update.sh is idempotent. If it fails, e.g. due to
compiler errors in piControl, just start it afresh. You are also welcome to
ask your questions in our community forum: https://revolutionpi.de/forum/

Note that since bullseye armv6 is no longer officially supported and is thus
disabled by default.

## Install build tools

```
apt-get install device-tree-compiler
apt-get install build-essential:native debhelper quilt bc
apt-get install bison flex libssl-dev rsync git
```

In addition a cross-compiler needs to be installed. The package depends on
the desired target architecture of the kernel:

**Packages for 32-bit kernel builds (v6 / v7 / v7l):**

```
apt-get install gcc-arm-linux-gnueabihf
```

**Packages for 64-bit kernel builds (v8):**

```
apt-get install gcc-aarch64-linux-gnu
```

## Get source code

> **NOTE:**  The repositories are cloned with truncated history, in order to
make fetching faster. If you need the full history, remove `--depth 1`
from the git commands.

```
git clone --depth 1 -b revpi-5.10 https://github.com/RevolutionPi/linux
git clone --depth 1 -b master https://github.com/RevolutionPi/piControl
git clone --depth 1 -b master https://github.com/RevolutionPi/kernelbakery
```

## Build kernel and packages

The 32-bit kernel runs on all Revolution Pi devices and is shipped with our
official images. As an alternative a 64-bit kernel can be built, which also
runs on all Revolution Pi devices with the exception of the first Core devices
(based on first generation of Raspberry Pi Compute Module).

### Build 32-bit kernel (v6 / v7 / v7l)

```
cd kernelbakery
LINUXDIR=$PWD/../linux PIKERNELMODDIR=$PWD/../piControl debian/update.sh
dpkg-buildpackage -a armhf -b -us -uc
```

To build the kernel for armv6, add `-a armv6`.

### Build 64-bit kernel (v8)

```
cd kernelbakery
ARCH=arm64 LINUXDIR=$PWD/../linux PIKERNELMODDIR=$PWD/../piControl debian/update.sh
dpkg-buildpackage -a arm64 -b -us -uc
```
