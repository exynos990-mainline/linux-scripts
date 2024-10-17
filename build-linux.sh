#!/bin/bash

set -e

dt_add_ramdisk()
{
	cp ${KERNEL_TREE}/arch/arm64/boot/dts/exynos/exynos990-${DEVICE}.dts bak.dts
	sed '/\	chosen {/a\
		bootargs = "root=/dev/mem0 initrd=0x84000000,0x1000000";\
		linux,initrd-start = <0x84000000>;\
		linux,initrd-end = <0x84FFFFFF>;' bak.dts | tee ${KERNEL_TREE}/arch/arm64/boot/dts/exynos/exynos990-${DEVICE}.dts
}

build_linux()
{
	if [ ! -d ${KERNEL_TREE} ]; then
		echo "Your kernel tree doesn't exist!"
		exit
	fi

	if [ ${ADD_INITRD} = 'y' ]; then
		echo "Adding initrd addresses..."
		dt_add_ramdisk
	fi

	cp ${ROOT}/990-configs/exynos990_defconfig ${KERNEL_TREE}/arch/arm64/configs/
	cd ${KERNEL_TREE}
	ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- make exynos990_defconfig
	ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- make -j$(nproc --all)
	echo Linux Kernel built.
	cd ${ROOT}
}

prepare_build_uni()
{
	cp ${KERNEL_TREE}/arch/arm64/boot/Image ${UNILOADER_TREE}/blob/Image
	cp ${KERNEL_TREE}/arch/arm64/boot/dts/exynos/exynos990-${DEVICE}.dtb ${UNILOADER_TREE}/blob/dtb

	if [ -f ${RAMDISK_BLOB} ]; then
		cp ${RAMDISK_BLOB} ${UNILOADER_TREE}/blob/ramdisk
	fi
	cd ${UNILOADER_TREE}

	# uniLoader lore
	make clean -j$(nproc --all)
}

uni_config_fixup()
{
	if ! grep -q "RAMDISK_ENTRY" configs/${DEVICE}_defconfig; then
		echo "FIXUP: uniLoader ramdisk entry address"
		echo "CONFIG_RAMDISK_ENTRY=0x84000000" >> configs/${DEVICE}_defconfig
	fi
}

pack()
{
	if [ ! -d ${UNILOADER_TREE} ]; then
		echo "Your uniLoader tree doesn't exist!"
		exit
	fi

	if [ "$DEVICE" = "x1slte" ]; then
		echo "x1slte, using x1s config."
		exit
	fi

	prepare_build_uni
	uni_config_fixup
	make ${DEVICE}_defconfig
	make -j$(nproc --all)

	mkbootimg --kernel uniLoader --base 0x10000000 --kernel_offset 0x00008000 --dtb_offset 0x01f00000 --dtb ~/phones/c1s/exy990-boot/boot.img-dtb --header_version 2 -o boot.img
	echo All done! Final img at: ${UNILOADER_TREE}/boot.img
	cd ${ROOT}
}

# Check env variables for device model
if [[ -z "${DEVICE}" ]]; then
	read -p "What device would you like to build for? (x1s/x1slte/c1s): " -r
	echo
	DEVICE=$REPLY
	echo "Tip: Set DEVICE env variable to do this automagically."
fi

# Check env variables for kernel srctree
if [[ -z "${KERNEL_TREE}" ]]; then
	echo "You need to set KERNEL_TREE to point to your kernel source."
	exit
fi

# Check env variables for uniLoader srctree
if [[ -z "${UNILOADER_TREE}" ]]; then
	echo "You need to set UNILOADER_TREE to point to your uniLoader source."
	exit
fi

# Keep the current dir for the end of the script
ROOT="$PWD"

# Check if we need to add initrd-{start,end} flags
if [[ -z "${ADD_INITRD}" ]]; then
	ADD_INITRD=n
	read -p "Would you like to add the default initramfs offset to the DT? (warning: changes will be temporary) (Y/n): " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		ADD_INITRD=y
	fi
	echo "Tip: Set ADD_INITRD env variable to do this automagically."
fi

echo "ADD_INITRD: ${ADD_INITRD}"
echo "ROOT: ${ROOT}"
echo "KERNEL_TREE: ${KERNEL_TREE}"
echo "UNILOADER_TREE: ${UNILOADER_TREE}"
echo "DEVICE: ${DEVICE}"
echo "RAMDISK_BLOB: ${RAMDISK_BLOB}"

_DEVICE=${DEVICE}
build_linux
pack

if [ -f "bak.dts" ]; then
	mv bak.dts ${KERNEL_TREE}/arch/arm64/boot/dts/exynos/exynos990-${_DEVICE}.dts
fi
