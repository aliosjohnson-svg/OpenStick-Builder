#!/bin/sh -e

DEVICE="${DEVICE:-uz801}"

# Map device → "LK2ND_COMPATIBLE LK2ND_BUNDLE_DTB"
# LK2ND_COMPATIBLE : compatible string lk2nd reports to the OS
# LK2ND_BUNDLE_DTB : DTB bundled into lk2nd for hardware init (all MSM8916
#                    512 MB sticks use the generic MTP DTB here)
get_lk2nd_params() {
    case "$1" in
        uz801)    echo "yiming,uz801-v3    msm8916-512mb-mtp.dtb" ;;
        ufi001c)  echo "thwc,ufi001c       msm8916-512mb-mtp.dtb" ;;
        ufi001b)  echo "thwc,ufi001b       msm8916-512mb-mtp.dtb" ;;
        jz02v10)  echo "jz,jz02-v10        msm8916-512mb-mtp.dtb" ;;
        ufi103s)  echo "thwc,ufi103s       msm8916-512mb-mtp.dtb" ;;
        qrzl903)  echo "qrzl,qrzl-903      msm8916-512mb-mtp.dtb" ;;
        w001)     echo "w,w001             msm8916-512mb-mtp.dtb" ;;
        ufi003)   echo "thwc,ufi003        msm8916-512mb-mtp.dtb" ;;
        mf32)     echo "mf,mf32            msm8916-512mb-mtp.dtb" ;;
        mf601)    echo "mf,mf601           msm8916-512mb-mtp.dtb" ;;
        wf2)      echo "wf,wf2             msm8916-512mb-mtp.dtb" ;;
        sp970v11) echo "sp970,sp970-v11    msm8916-512mb-mtp.dtb" ;;
        sp970v10) echo "sp970,sp970-v10    msm8916-512mb-mtp.dtb" ;;
        *)
            echo "[aboot] Unknown device '${DEVICE}', falling back to uz801" >&2
            echo "yiming,uz801-v3    msm8916-512mb-mtp.dtb"
            ;;
    esac
}

PARAMS="$(get_lk2nd_params "${DEVICE}")"
LK2ND_COMPATIBLE="$(echo "${PARAMS}" | awk '{print $1}')"
LK2ND_BUNDLE_DTB="$(echo "${PARAMS}"  | awk '{print $2}')"

echo "[aboot] Device          : ${DEVICE}"
echo "[aboot] lk2nd compatible: ${LK2ND_COMPATIBLE}"
echo "[aboot] lk2nd bundle DTB: ${LK2ND_BUNDLE_DTB}"

make -C src/qhypstub CROSS_COMPILE=aarch64-linux-gnu-

# patch to reduce mmc speed as some boards have intermittent failures when
# inititalizing the mmc (maybe due to using old/recycled flash chips)
echo 'DEFINES += USE_TARGET_HS200_CAPS=1' >> src/lk2nd/project/lk1st-msm8916.mk

make -C src/lk2nd \
    "LK2ND_BUNDLE_DTB=${LK2ND_BUNDLE_DTB}" \
    "LK2ND_COMPATIBLE=${LK2ND_COMPATIBLE}" \
    TOOLCHAIN_PREFIX=arm-none-eabi- \
    lk1st-msm8916

# test sign
mkdir -p files
src/qtestsign/qtestsign.py hyp src/qhypstub/qhypstub.elf \
    -o files/hyp.mbn
src/qtestsign/qtestsign.py aboot src/lk2nd/build-lk1st-msm8916/emmc_appsboot.mbn \
    -o files/aboot.mbn
