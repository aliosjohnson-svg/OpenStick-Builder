#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}
RELEASE=${RELEASE=bookworm}
HOST_NAME=${HOST_NAME=openstick}

rm -rf ${CHROOT}

debootstrap --foreign --arch arm64 \
    --keyring /usr/share/keyrings/debian-archive-keyring.gpg ${RELEASE} ${CHROOT}

cp $(which qemu-aarch64-static) ${CHROOT}/usr/bin

chroot ${CHROOT} qemu-aarch64-static /bin/bash /debootstrap/debootstrap --second-stage

cat << EOF > ${CHROOT}/etc/apt/sources.list
deb http://deb.debian.org/debian ${RELEASE} main contrib non-free-firmware
deb http://deb.debian.org/debian-security/ ${RELEASE}-security main contrib non-free-firmware
deb http://deb.debian.org/debian ${RELEASE}-updates main contrib non-free-firmware
EOF

mount -t proc proc ${CHROOT}/proc/
mount -t sysfs sys ${CHROOT}/sys/
mount -o bind /dev/ ${CHROOT}/dev/
mount -o bind /dev/pts/ ${CHROOT}/dev/pts/
mount -o bind /run ${CHROOT}/run/

# chroot setup
cp configs/install_dnsproxy.sh ${CHROOT}
cp scripts/setup.sh ${CHROOT}
chroot ${CHROOT} qemu-aarch64-static /bin/sh -c /setup.sh

# cleanup
for a in proc sys dev/pts dev run; do
    umount ${CHROOT}/${a}
done;

rm ${CHROOT}/install_dnsproxy.sh
rm -f ${CHROOT}/setup.sh
echo -n > ${CHROOT}/root/.bash_history

echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# setup dnsmasq
cp -a configs/dhcp.conf ${CHROOT}/etc/dnsmasq.d/dhcp.conf

cat <<EOF > ${CHROOT}/etc/resolv.conf
search lan
nameserver 127.0.0.1
options edns0 trust-ad
EOF

cat <<EOF >> ${CHROOT}/etc/hosts

192.168.100.1	${HOST_NAME}
EOF

# add rc-local
cp -a configs/rc.local ${CHROOT}/etc/rc.local
chmod +x ${CHROOT}/etc/rc.local

# add interfaces (ifupdown2)
cp -a configs/interfaces ${CHROOT}/etc/network/

# add MSM8916 USB gadget
cp -a configs/msm8916-usb-gadget.sh ${CHROOT}/usr/sbin/
cp configs/msm8916-usb-gadget.conf ${CHROOT}/etc/

# setup systemd services
cp -a configs/system/* ${CHROOT}/etc/systemd/system

cp -a scripts/msm-firmware-loader.sh ${CHROOT}/usr/sbin

# setup NetworkManager
cp configs/*.nmconnection ${CHROOT}/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/etc/NetworkManager/system-connections/*
cp configs/99-custom.conf ${CHROOT}/etc/NetworkManager/conf.d/

# Map device → kernel DTB filename.
# DTBs come from the locally compiled immortalwrt kernel; repo dtbs/ are
# used as extras/overrides for devices not yet upstream in the kernel.
DEVICE="${DEVICE:-uz801}"
get_kernel_dtb() {
    case "$1" in
        uz801)    echo "msm8916-yiming-uz801v3.dtb"  ;;
        ufi001c)  echo "msm8916-thwc-ufi001c.dtb"    ;;
        ufi001b)  echo "msm8916-thwc-ufi001b.dtb"    ;;
        jz02v10)  echo "msm8916-jz01-45-v33.dtb"     ;;
        ufi103s)  echo "msm8916-thwc-ufi103s.dtb"    ;;
        qrzl903)  echo "msm8916-yiming-uz801v3.dtb"  ;;
        w001)     echo "msm8916-yiming-uz801v3.dtb"  ;;
        ufi003)   echo "msm8916-thwc-ufi003.dtb"     ;;
        mf32)     echo "msm8916-fy-mf800.dtb"        ;;
        mf601)    echo "msm8916-fy-mf800.dtb"        ;;
        wf2)      echo "msm8916-yiming-uz801v3.dtb"  ;;
        sp970v11) echo "msm8916-yiming-uz801v3.dtb"  ;;
        sp970v10) echo "msm8916-yiming-uz801v3.dtb"  ;;
        *)        echo "msm8916-yiming-uz801v3.dtb"  ;;
    esac
}
KERNEL_DTB="$(get_kernel_dtb "${DEVICE}")"

# install kernel from locally compiled immortalwrt build
echo "[rootfs] Installing kernel (device: ${DEVICE}, DTB: ${KERNEL_DTB})..."
tar xpzf files/kernel.tar.gz -C ${CHROOT}

# copy repo-provided custom DTBs — these supplement/override kernel DTBs
# for devices whose DTS is not yet merged upstream
cp dtbs/* ${CHROOT}/boot/dtbs/qcom/ 2>/dev/null || true

# verify the selected DTB exists; fall back to uz801 if missing
if [ ! -f "${CHROOT}/boot/dtbs/qcom/${KERNEL_DTB}" ]; then
    echo "[rootfs] WARNING: ${KERNEL_DTB} not found; falling back to msm8916-yiming-uz801v3.dtb"
    KERNEL_DTB="msm8916-yiming-uz801v3.dtb"
fi

mkdir -p ${CHROOT}/boot/extlinux
cat > ${CHROOT}/boot/extlinux/extlinux.conf << EOF
linux /vmlinuz
fdt /dtbs/qcom/${KERNEL_DTB}
append earlycon root=PARTUUID=a7ab80e8-e9d1-e8cd-f157-93f69b1d141e console=ttyMSM0,115200 no_framebuffer=true rw rootwait
EOF

# create missing directory
mkdir -p ${CHROOT}/lib/firmware/msm-firmware-loader

# update fstab
echo "PARTUUID=80780b1d-0fe1-27d3-23e4-9244e62f8c46\t/boot\text2\tdefaults\t0 2" > ${CHROOT}/etc/fstab

# backup rootfs
tar cpzf rootfs.tgz --exclude="usr/bin/qemu-aarch64-static" -C rootfs .

cat <<EOF > ${CHROOT}/etc/resolv.conf
nameserver 1.1.1.1
EOF
