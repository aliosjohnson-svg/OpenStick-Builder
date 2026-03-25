#!/bin/sh -e
# Build MSM8916 kernel from immortalwrt source.
# Produces files/kernel.tar.gz containing:
#   boot/vmlinuz          - kernel image
#   boot/dtbs/qcom/*.dtb  - device trees
#   boot/kernel-version   - kernel release string
#   lib/modules/<ver>/    - kernel modules

IMMORTALWRT_URL="${IMMORTALWRT_URL:-https://github.com/xuxin1955/immortalwrt}"
IMMORTALWRT_BRANCH="${IMMORTALWRT_BRANCH:-master}"
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
WORK_DIR="$(pwd)"
KERNEL_OUTDIR="${WORK_DIR}/kernel-pkg"

echo "[kernel] Cloning immortalwrt (sparse checkout for kernel config + patches)..."
git clone --depth=1 -b "${IMMORTALWRT_BRANCH}" \
    --filter=blob:limit=5m \
    --no-checkout \
    "${IMMORTALWRT_URL}" /tmp/immortalwrt-src

cd /tmp/immortalwrt-src
git sparse-checkout init --cone
git sparse-checkout set \
    include \
    target/linux/msm89xx \
    target/linux/generic
git checkout

# Parse kernel patch version (e.g. "6.12") from include/kernel-version.mk
PATCHVER=""
if [ -f "include/kernel-version.mk" ]; then
    PATCHVER=$(grep -m1 'LINUX_KERNEL_PATCHVER' include/kernel-version.mk | \
        awk -F':=' '{print $2}' | tr -d ' \t')
fi

# Parse exact kernel version (e.g. "6.12.15")
KVER=""
if [ -f "include/kernel-version.mk" ] && [ -n "$PATCHVER" ]; then
    SUBVER=$(grep "^LINUX_VERSION-${PATCHVER}" include/kernel-version.mk | \
        awk -F'= ' '{print $2}' | tr -d ' \t')
    [ -n "$SUBVER" ] && KVER="${PATCHVER}${SUBVER}"
fi

# Fallback: try target-specific Makefile
if [ -z "$KVER" ] && [ -f "target/linux/msm89xx/Makefile" ]; then
    KVER=$(grep -m1 'LINUX_VERSION' target/linux/msm89xx/Makefile | \
        awk -F':=' '{print $2}' | tr -d ' \t')
fi

if [ -z "$KVER" ]; then
    echo "[kernel] WARNING: Could not detect kernel version; defaulting to 6.12.0"
    KVER="6.12.0"
    PATCHVER="6.12"
fi

[ -z "$PATCHVER" ] && PATCHVER="$(echo "$KVER" | cut -d. -f1-2)"
MAJOR="$(echo "$KVER" | cut -d. -f1)"

echo "[kernel] Version: ${KVER}  (patchver: ${PATCHVER})"

# Download kernel source from kernel.org
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/linux-${KVER}.tar.xz"
echo "[kernel] Downloading ${KERNEL_URL}..."
wget -q --show-progress "${KERNEL_URL}" -O "/tmp/linux-${KVER}.tar.xz"

echo "[kernel] Extracting..."
tar xf "/tmp/linux-${KVER}.tar.xz" -C /tmp
LINUX_DIR="/tmp/linux-${KVER}"

# Apply OpenWrt patches (failures are warnings, not errors)
apply_patches() {
    dir="$1"
    [ -d "$dir" ] || return 0
    for p in "${dir}"/*.patch; do
        [ -f "$p" ] || continue
        echo "  [patch] $(basename "$p")"
        patch --quiet -p1 -d "${LINUX_DIR}" < "$p" 2>/dev/null || \
            echo "  [warn] $(basename "$p") had issues, continuing"
    done
}

echo "[kernel] Applying patches..."
apply_patches "target/linux/generic/backport-${PATCHVER}"
apply_patches "target/linux/generic/pending-${PATCHVER}"
apply_patches "target/linux/msm89xx/patches-${PATCHVER}"

# Merge generic + target-specific kernel configs
echo "[kernel] Configuring..."
> /tmp/kconfig.merged
[ -f "target/linux/generic/config-${PATCHVER}" ] && \
    cat "target/linux/generic/config-${PATCHVER}" >> /tmp/kconfig.merged
[ -f "target/linux/msm89xx/config-${PATCHVER}" ] && \
    cat "target/linux/msm89xx/config-${PATCHVER}" >> /tmp/kconfig.merged

cd "${LINUX_DIR}"
if [ -s /tmp/kconfig.merged ]; then
    cp /tmp/kconfig.merged .config
    ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} make olddefconfig
else
    echo "[kernel] No merged config found; using defconfig"
    ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} make defconfig
fi

# Compile
echo "[kernel] Compiling (this takes ~30-60 minutes)..."
ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} make -j"$(nproc)" Image.gz dtbs modules

KRELEASE="$(cat include/config/kernel.release 2>/dev/null || echo "${KVER}")"
echo "[kernel] Built: ${KRELEASE}"

# Install modules into a staging dir
mkdir -p /tmp/kernel-install
ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} \
    make INSTALL_MOD_PATH=/tmp/kernel-install modules_install

# Collect output
mkdir -p "${KERNEL_OUTDIR}/boot/dtbs/qcom"
cp arch/arm64/boot/Image.gz "${KERNEL_OUTDIR}/boot/vmlinuz"
find arch/arm64/boot/dts/qcom -name "msm8916-*.dtb" \
    -exec cp {} "${KERNEL_OUTDIR}/boot/dtbs/qcom/" \; 2>/dev/null || true
cp -r /tmp/kernel-install/lib "${KERNEL_OUTDIR}/"
echo "${KRELEASE}" > "${KERNEL_OUTDIR}/boot/kernel-version"

echo "[kernel] MSM8916 DTBs produced:"
ls "${KERNEL_OUTDIR}/boot/dtbs/qcom/" || echo "  (none)"

# Archive for use by debootstrap
mkdir -p "${WORK_DIR}/files"
tar czf "${WORK_DIR}/files/kernel.tar.gz" -C "${KERNEL_OUTDIR}" .
echo "[kernel] Packaged to files/kernel.tar.gz"
