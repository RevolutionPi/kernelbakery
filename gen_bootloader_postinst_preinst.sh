#!/bin/sh

if ! [ -d ./boot ]; then
  printf "Can't find boot dir.\n"
  exit 1
fi

version=`cat ./extra/uname_string | cut -f 3 -d ' '| sed -Ee 's/(-v[78]l?)?\+$//'`
kernel_postinst="debian/raspberrypi-kernel.postinst"
kernel_preinst="debian/raspberrypi-kernel.preinst"

printf "#!/bin/sh\n" > $kernel_postinst
printf "#!/bin/sh\n" > $kernel_preinst

printf "mkdir -p /usr/share/rpikernelhack/overlays\n" >$kernel_preinst
printf "mkdir -p /boot/overlays\n" >$kernel_preinst

for FN in ./boot/*.dtb ./boot/kernel*.img ./boot/COPYING.linux ./boot/overlays/*; do
  if ! [ -d "$FN" ]; then
    FN=${FN#../boot/}
    printf "rm -f /boot/$FN\n" >$kernel_postinst
    printf "dpkg-divert --package rpikernelhack --remove --rename /boot/$FN\n" >$kernel_postinst
    printf "sync\n" >$kernel_postinst

    printf "dpkg-divert --package rpikernelhack --rename --divert /usr/share/rpikernelhack/$FN /boot/$FN\n" >$kernel_preinst
  fi
done

cat <<EOF >$kernel_preinst
export INITRD=No
if [ -d "/etc/kernel/preinst.d" ]; then
  run-parts -v --report --exit-on-error --arg=${version}+ --arg=/boot/kernel.img /etc/kernel/preinst.d
  run-parts -v --report --exit-on-error --arg=${version}-v7+ --arg=/boot/kernel7.img /etc/kernel/preinst.d
  run-parts -v --report --exit-on-error --arg=${version}-v7l+ --arg=/boot/kernel7l.img /etc/kernel/preinst.d
  run-parts -v --report --exit-on-error --arg=${version}-v8+ --arg=/boot/kernel8.img /etc/kernel/preinst.d
fi
if [ -d "/etc/kernel/preinst.d/${version}+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}+ --arg=/boot/kernel.img /etc/kernel/preinst.d/${version}+
fi
if [ -d "/etc/kernel/preinst.d/${version}-v7+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v7+ --arg=/boot/kernel7.img /etc/kernel/preinst.d/${version}-v7+
fi
if [ -d "/etc/kernel/preinst.d/${version}-v7l+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v7l+ --arg=/boot/kernel7l.img /etc/kernel/preinst.d/${version}-v7l+
fi
if [ -d "/etc/kernel/preinst.d/${version}-v8+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v8+ --arg=/boot/kernel8.img /etc/kernel/preinst.d/${version}-v8+
fi
EOF

cat <<EOF >$kernel_postinst
export INITRD=No
if [ -d "/etc/kernel/postinst.d" ]; then
  run-parts -v --report --exit-on-error --arg=${version}+ --arg=/boot/kernel.img /etc/kernel/postinst.d
  run-parts -v --report --exit-on-error --arg=${version}-v7+ --arg=/boot/kernel7.img /etc/kernel/postinst.d
  run-parts -v --report --exit-on-error --arg=${version}-v7l+ --arg=/boot/kernel7l.img /etc/kernel/postinst.d
  run-parts -v --report --exit-on-error --arg=${version}-v8+ --arg=/boot/kernel8.img /etc/kernel/postinst.d
fi
if [ -d "/etc/kernel/postinst.d/${version}+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}+ --arg=/boot/kernel.img /etc/kernel/postinst.d/${version}+
fi
if [ -d "/etc/kernel/postinst.d/${version}-v7+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v7+ --arg=/boot/kernel7.img /etc/kernel/postinst.d/${version}-v7+
fi
if [ -d "/etc/kernel/postinst.d/${version}-v7l+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v7l+ --arg=/boot/kernel7l.img /etc/kernel/postinst.d/${version}-v7l+
fi
if [ -d "/etc/kernel/postinst.d/${version}-v8+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v8+ --arg=/boot/kernel8.img /etc/kernel/postinst.d/${version}-v8+
fi

# wheezy and jessie images shipped with a "kunbus" overlay
/bin/sed -i -e 's/^dtoverlay=kunbus/dtoverlay=revpi-core/' /boot/config.txt

# wheezy and jessie images enabled this RTC which is now
# duplicated by "revpi-core" overlay
/bin/sed -i -e '/^dtoverlay=i2c-rtc,pcf2127$/d' /boot/config.txt

# update dt-blob.bin
/bin/sed -n -e '/^dtoverlay=revpi-/s/^dtoverlay=//p' /boot/config.txt |
  while read machine ; do
    if [ -e "/boot/overlays/\${machine}-dt-blob.dtbo" ] ; then
      /bin/cp "/boot/overlays/\${machine}-dt-blob.dtbo" /boot/dt-blob.bin
    fi
  done

# 8192cu is unreliable on 4.9, blacklist it and unblacklist rtl8192cu
if ! /bin/grep -Eq "^blacklist 8192cu" /etc/modprobe.d/blacklist-rtl8192cu.conf ; then
  echo "blacklist 8192cu" >> /etc/modprobe.d/blacklist-rtl8192cu.conf
fi
/bin/sed -i -e '/^blacklist rtl8192cu/s/^/#/' /etc/modprobe.d/blacklist-rtl8192cu.conf

# Remove deprecated "elevator=deadline" from the cmdline.txt
# We will only do anything if we are certain that the user has not modfified the
# relevant part of the cmdline.
if /bin/grep -Fq "rootfstype=ext4 elevator=deadline fsck.repair=yes" /boot/cmdline.txt ; then
  sed -i -e 's/rootfstype=ext4 elevator=deadline fsck.repair=yes/rootfstype=ext4 fsck.repair=yes/' /boot/cmdline.txt
fi
EOF

printf "#DEBHELPER#\n" >$kernel_postinst
printf "#DEBHELPER#\n" >$kernel_preinst

printf "#!/bin/sh\n" > debian/raspberrypi-kernel.prerm
printf "#!/bin/sh\n" > debian/raspberrypi-kernel.postrm
printf "#!/bin/sh\n" > debian/raspberrypi-kernel-headers.postinst

cat <<EOF >> debian/raspberrypi-kernel.prerm
export INITRD=No
if [ -d "/etc/kernel/prerm.d" ]; then
  run-parts -v --report --exit-on-error --arg=${version}+ --arg=/boot/kernel.img /etc/kernel/prerm.d
  run-parts -v --report --exit-on-error --arg=${version}-v7+ --arg=/boot/kernel7.img /etc/kernel/prerm.d
  run-parts -v --report --exit-on-error --arg=${version}-v7l+ --arg=/boot/kernel7l.img /etc/kernel/prerm.d
  run-parts -v --report --exit-on-error --arg=${version}-v8+ --arg=/boot/kernel8.img /etc/kernel/prerm.d
fi
if [ -d "/etc/kernel/prerm.d/${version}+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}+ --arg=/boot/kernel.img /etc/kernel/prerm.d/${version}+
fi
if [ -d "/etc/kernel/prerm.d/${version}-v7+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v7+ --arg=/boot/kernel7.img /etc/kernel/prerm.d/${version}-v7+
fi
if [ -d "/etc/kernel/prerm.d/${version}-v7l+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v7l+ --arg=/boot/kernel7l.img /etc/kernel/prerm.d/${version}-v7l+
fi
if [ -d "/etc/kernel/prerm.d/${version}-v8+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v8+ --arg=/boot/kernel8.img /etc/kernel/prerm.d/${version}-v8+
fi
EOF

cat <<EOF >> debian/raspberrypi-kernel.postrm
export INITRD=No
if [ -d "/etc/kernel/postrm.d" ]; then
  run-parts -v --report --exit-on-error --arg=${version}+ --arg=/boot/kernel.img /etc/kernel/postrm.d
  run-parts -v --report --exit-on-error --arg=${version}-v7+ --arg=/boot/kernel7.img /etc/kernel/postrm.d
  run-parts -v --report --exit-on-error --arg=${version}-v7l+ --arg=/boot/kernel7l.img /etc/kernel/postrm.d
  run-parts -v --report --exit-on-error --arg=${version}-v8+ --arg=/boot/kernel8.img /etc/kernel/postrm.d
fi
if [ -d "/etc/kernel/postrm.d/${version}+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}+ --arg=/boot/kernel.img /etc/kernel/postrm.d/${version}+
fi
if [ -d "/etc/kernel/postrm.d/${version}-v7+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v7+ --arg=/boot/kernel7.img /etc/kernel/postrm.d/${version}-v7+
fi
if [ -d "/etc/kernel/postrm.d/${version}-v7l+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v7l+ --arg=/boot/kernel7l.img /etc/kernel/postrm.d/${version}-v7l+
fi
if [ -d "/etc/kernel/postrm.d/${version}-v8+" ]; then
  run-parts -v --report --exit-on-error --arg=${version}-v8+ --arg=/boot/kernel8.img /etc/kernel/postrm.d/${version}-v8+
fi
EOF

cat <<EOF >> debian/raspberrypi-kernel-headers.postinst
export INITRD=No
if [ -d "/etc/kernel/header_postinst.d" ]; then
  run-parts -v --verbose --exit-on-error --arg=${version}+ /etc/kernel/header_postinst.d
  run-parts -v --verbose --exit-on-error --arg=${version}-v7+ /etc/kernel/header_postinst.d
  run-parts -v --verbose --exit-on-error --arg=${version}-v7l+ /etc/kernel/header_postinst.d
  run-parts -v --verbose --exit-on-error --arg=${version}-v8+ /etc/kernel/header_postinst.d
fi

if [ -d "/etc/kernel/header_postinst.d/${version}+" ]; then
  run-parts -v --verbose --exit-on-error --arg=${version}+ /etc/kernel/header_postinst.d/${version}+
fi

if [ -d "/etc/kernel/header_postinst.d/${version}-v7+" ]; then
  run-parts -v --verbose --exit-on-error --arg=${version}-v7+ /etc/kernel/header_postinst.d/${version}-v7+
fi

if [ -d "/etc/kernel/header_postinst.d/${version}-v7l+" ]; then
  run-parts -v --verbose --exit-on-error --arg=${version}-v7l+ /etc/kernel/header_postinst.d/${version}-v7l+
fi

if [ -d "/etc/kernel/header_postinst.d/${version}-v8+" ]; then
  run-parts -v --verbose --exit-on-error --arg=${version}-v8+ /etc/kernel/header_postinst.d/${version}-v8+
fi
EOF

printf "#DEBHELPER#\n" >> debian/raspberrypi-kernel.prerm
printf "#DEBHELPER#\n" >> debian/raspberrypi-kernel.postrm
printf "#DEBHELPER#\n" >> debian/raspberrypi-kernel-headers.postinst
