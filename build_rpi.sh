#!/bin/bash

# sudo apt-get install qemu-user-static debootstrap git

if [ $(id -u) -ne 0 ]
then
    echo "This scripts must be run as root"
    exit 1
fi

BUILD_HOME=${HOME}/raspbian
RELEASE=jessie
ROOTFS=${BUILD_HOME}/${RELEASE}
ROUTER=${HOME}/homer/router
MIRROR="http://mirrors.zju.edu.cn/raspbian/raspbian/"
MODULES=${BUILD_HOME}/rtl8188eu
NOW=`date +%Y_%m_%d`

installation () {
    mkdir -p ${ROOTFS}
    qemu-debootstrap --arch armhf ${RELEASE} ${ROOTFS} ${MIRROR}

    mount -t proc proc ${ROOTFS}/proc
    mount -t sysfs sysfs ${ROOTFS}/sys

    git clone https://github.com/lwfinger/rtl8188eu.git --depth 1 ${BUILD_HOME}/rtl8188eu
    git clone https://github.com/raspberrypi/firmware.git --depth 1 ${BUILD_HOME}/firmware

    cp -R ${BUILD_HOME}/firmware/hardfp/opt/* ${ROOTFS}/opt/
    cp -R ${BUILD_HOME}/firmware/modules ${ROOTFS}/lib/
    cp -R ${BUILD_HOME}/firmware/boot/* ${ROOTFS}/boot/

    echo "deb ${MIRROR} ${RELEASE} main contrib non-free rpi" > ${ROOTFS}/etc/apt/sources.list

    echo "qhome" > ${ROOTFS}/etc/hostname
    echo -e "127.0.0.1\tqhome" >> ${ROOTFS}/etc/hosts

    echo -e "proc\t/proc\tproc\tdefaults\t0\t0" > ${ROOTFS}/etc/fstab
    echo -e "/dev/mmcblk0p1\t/boot\tvfat\tdefaults\t0\t0" >> ${ROOTFS}/etc/fstab
    echo -e "/dev/sda2\t/\text4\tdefaults,noatime,discard\t0\t1" >> ${ROOTFS}/etc/fstab
    echo -e "/dev/sda1\tnone\tswap\tdefaults\t0\t0" >> ${ROOTFS}/etc/fstab

    sed -i '/\/usr\/games/s/\/usr\/local\/bin:\/usr\/bin:\/bin/\/usr\/local\/sbin:\/usr\/local\/bin:\/usr\/sbin:\/usr\/bin:\/sbin:\/bin/g' ${ROOTFS}/etc/profile

    sed -i 's/KERNEL\!=\"eth\*|ath\*|wlan\*\[0\-9\]/KERNEL\!=\"ath\*/g' ${ROOTFS}/lib/udev/rules.d/75-persistent-net-generator.rules
    rm -f ${ROOTFS}/etc/udev/rules.d/70-persistent-net.rules

    sed -i 's/^#FSCKFIX=no/FSCKFIX=yes/g' ${ROOTFS}/etc/default/rcS

    echo "LC_ALL=C" >> ${ROOTFS}/etc/default/locale
    echo "LANGUAGE=en_US.UTF-8" >> ${ROOTFS}/etc/default/locale
    echo "LANG=en_US.UTF-8" >> ${ROOTFS}/etc/default/locale

    mkdir ${ROOTFS}/etc/rsyncd

    # chroot into the Raspbian filesystem
    echo "#!/bin/sh

    export HOME=/root
    export LC_ALL=C

    wget http://mirrors.ustc.edu.cn/raspbian/raspbian.public.key -O - | apt-key add -
    apt-get update

    apt-get install -y locales dhcpcd sudo openssh-server ifplugd ntp patch less vim rsync mpd mpc alsa-utils wpasupplicant wireless-tools firmware-atheros firmware-libertas firmware-ralink firmware-realtek firmware-brcm80211
    apt-get clean

    systemctl stop mpd
    systemctl enable mpd
    systemctl enable rsync

    sed -i 's/^# en_US.UTF-8/en_US UTF-8/g' /etc/locale.gen

    locale-gen
    update-locale

    rm /etc/localtime
    ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    groupadd pi
    useradd -m -g pi -G adm,dialout,sudo,audio,video,plugdev,games,users,netdev -s /bin/bash pi
    echo "pi:raspberry" | chpasswd

    chmod 777 /var/lib/mpd/music
    chmod 777 /var/lib/mpd/playlists

    echo "snd-bcm2835" >> /etc/modules
    echo "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev" > /etc/wpa_supplicant/wpa_supplicant.conf
    echo "update_config=1" >> /etc/wpa_supplicant/wpa_supplicant.conf

    sync
    exit 0" > ${ROOTFS}/config.sh

    chmod +x ${ROOTFS}/config.sh

    LC_ALL=C chroot ${ROOTFS} /config.sh

    echo "pi ALL=(ALL) NOPASSWD: ALL" >> ${ROOTFS}/etc/sudoers

    sed -i 's/^INTERFACES=\"/INTERFACES=\"auto/g' ${ROOTFS}/etc/default/ifplugd
    sed -i 's/^HOTPLUG_INTERFACES=\"/HOTPLUG_INTERFACES=\"all/g' ${ROOTFS}/etc/default/ifplugd

    cp -R ${BUILD_HOME}/rtl8188eu/rtl8188eufw.bin ${ROOTFS}/lib/firmware/rtlwifi/

}

main () {
    if [ -e "${BUILD_HOME}/${RELEASE}" ]
    then
        git clone https://github.com/lwfinger/rtl8188eu.git --depth 1 ${BUILD_HOME}/rtl8188eu
        git clone https://github.com/raspberrypi/firmware.git --depth 1 ${BUILD_HOME}/firmware

        rm -rf ${ROOTFS}/opt/vc
        rm -rf ${ROOTFS}/lib/modules
        rm -rf ${ROOTFS}/boot/*

        cp -R ${BUILD_HOME}/firmware/hardfp/opt/* ${ROOTFS}/opt/
        cp -R ${BUILD_HOME}/firmware/modules ${ROOTFS}/lib/
        cp -R ${BUILD_HOME}/firmware/boot/* ${ROOTFS}/boot/
        cp -R ${BUILD_HOME}/rtl8188eu/rtl8188eufw.bin ${ROOTFS}/lib/firmware/rtlwifi/

        echo "#!/bin/sh
        apt-get update
        apt-get upgrade -y
        apt-get clean" > ${ROOTFS}/config.sh

        chmod +x ${ROOTFS}/config.sh

        mount -t proc proc ${ROOTFS}/proc
        mount -t sysfs sysfs ${ROOTFS}/sys

    else
        installation
    fi

    LC_ALL=C chroot ${ROOTFS} /config.sh

    PID=$(pgrep mpd)
    if [ ! -z ${PID} ]
    then
        kill -9 ${PID}
    fi

    umount --force ${ROOTFS}/proc
    umount --force ${ROOTFS}/sys

    echo "root=/dev/sda2 rw rootwait console=ttyAMA0,115200 console=tty1 plymouth.enable=0 smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 kgdboc=ttyAMA0,115200 elevator=noop" > ${ROOTFS}/boot/cmdline.txt
    echo "" > ${ROOTFS}/boot/config.txt

    cp ${ROUTER}/music/crontab ${ROOTFS}/etc/
    cp ${ROUTER}/music/gen.sh ${ROOTFS}/home/pi/
    cp ${ROUTER}/music/rsync ${ROOTFS}/etc/default/
    cp ${ROUTER}/music/mpd.conf ${ROOTFS}/etc/
    cp ${ROUTER}/music/mpd.init ${ROOTFS}/etc/init.d/mpd
    cp ${ROUTER}/music/interfaces ${ROOTFS}/etc/network/
    cp ${ROUTER}/music/rsyncd.conf ${ROOTFS}/etc/
    cp ${ROUTER}/music/rsyncd.motd ${ROOTFS}/etc/rsyncd/
    cp ${ROUTER}/music/rsyncd.secrets ${ROOTFS}/etc/rsyncd/
    cp ${ROUTER}/music/sshd_config ${ROOTFS}/etc/ssh
    cp ${ROUTER}/music/testwifi.sh ${ROOTFS}/usr/local/bin/testwifi.sh

    chmod 600 ${ROOTFS}/etc/rsyncd/rsyncd.secrets
    rm ${ROOTFS}/config.sh
    rm -rf ${BUILD_HOME}/firmware ${BUILD_HOME}/rtl8188eu

    cd ${ROOTFS}
    tar -czf ${BUILD_HOME}/qhome_music_${RELEASE}_${NOW}.tar.gz *

    return
}

main

exit 0
