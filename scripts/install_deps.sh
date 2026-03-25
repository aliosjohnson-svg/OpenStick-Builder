#!/bin/sh -e

apt update
apt install -y \
    android-sdk-libsparse-utils \
    autoconf \
    automake \
    bc \
    binfmt-support \
    bison \
    cmake \
    debian-archive-keyring \
    debootstrap \
    device-tree-compiler \
    fdisk \
    flex \
    g++-aarch64-linux-gnu \
    gcc-aarch64-linux-gnu \
    gcc-arm-none-eabi \
    git \
    libelf-dev \
    libssl-dev \
    libtool \
    make \
    pkg-config \
    python3-cryptography \
    python3-pyasn1-modules \
    python3-pycryptodome \
    qemu-user-static \
    unzip \
    wget
