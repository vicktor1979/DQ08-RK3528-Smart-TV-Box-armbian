#!/bin/bash
set -e

KDIR="./cache/sources/linux-kernel-worktree/5.10__rk3528-tvbox__arm64"
CFG="$KDIR/.config"

if [ ! -f "$CFG" ]; then
  echo "Nem találom a kernel configot: $CFG"
  echo "Előbb egyszer indíts kernel configos buildet."
  exit 1
fi

cd "$KDIR"

echo "[1] COMPILE_TEST bekapcsolása..."
./scripts/config --file .config -e COMPILE_TEST

echo "[2] BTF kikapcsolása..."
./scripts/config --file .config -d DEBUG_INFO_BTF

echo "[3] MMC / SDIO / RFKILL / firmware alapok..."
./scripts/config --file .config \
  -e MMC \
  -e MMC_BLOCK \
  -e MMC_SDHCI \
  -e MMC_DW \
  -e MMC_DW_ROCKCHIP \
  -e RFKILL \
  -e CFG80211 \
  -e MAC80211 \
  -e FW_LOADER \
  -e EXTRA_FIRMWARE

echo "[4] USB hálózat / WiFi alapok modulba..."
./scripts/config --file .config \
  -m USB_NET_DRIVERS \
  -m USB_USBNET \
  -m USB_NET_CDCETHER \
  -m USB_NET_RNDIS_HOST \
  -m USB_NET_CDC_NCM \
  -m USB_NET_CDC_MBIM \
  -m USB_NET_AX8817X \
  -m USB_NET_AX88179_178A \
  -m USB_NET_SMSC75XX \
  -m USB_NET_SMSC95XX \
  -m USB_NET_RTL8150 \
  -m USB_RTL8152

echo "[5] WiFi családok modulba..."
./scripts/config --file .config \
  -m WLAN \
  -m WLAN_VENDOR_REALTEK \
  -m WLAN_VENDOR_RALINK \
  -m WLAN_VENDOR_MEDIATEK \
  -m WLAN_VENDOR_BROADCOM \
  -m WLAN_VENDOR_ATH \
  -m WLAN_VENDOR_INTEL \
  -m WLAN_VENDOR_MARVELL \
  -m WLAN_VENDOR_QUANTENNA \
  -m WLAN_VENDOR_TI \
  -m WLAN_VENDOR_ZYDAS

echo "[6] Realtek driverek modulba..."
./scripts/config --file .config \
  -m RTL8188EE \
  -m RTL8192CE \
  -m RTL8192SE \
  -m RTL8192DE \
  -m RTL8723AE \
  -m RTL8723BE \
  -m RTL8188EU \
  -m RTL8192CU \
  -m RTL8XXXU \
  -m RTL8XXXU_UNTESTED \
  -m RTL8723BS \
  -m RTL8723CS \
  -m RTL8723DS \
  -m RTL8821CS \
  -m RTL8822BS \
  -m RTL8822BE \
  -m RTL8822BU \
  -m RTL8852BE \
  -m RTL8852BU

echo "[7] Broadcom / Cypress driverek modulba..."
./scripts/config --file .config \
  -m BRCMUTIL \
  -m BRCMFMAC \
  -m BRCMFMAC_PROTO_BCDC \
  -m BRCMFMAC_SDIO \
  -m BRCMFMAC_USB \
  -m BRCMFMAC_PCIE \
  -m BCMDHD \
  -e BCMDHD_SDIO \
  -d BCMDHD_PCIE \
  -d CYW_BCMDHD \
  -d INFINEON_DHD

echo "[8] MediaTek / Ralink WiFi modulba..."
./scripts/config --file .config \
  -m MT7601U \
  -m MT76_CORE \
  -m MT76_USB \
  -m MT76_SDIO \
  -m MT76x0U \
  -m MT76x2U \
  -m MT7603E \
  -m MT7615E \
  -m MT7663_USB_SDIO_COMMON \
  -m MT7663U \
  -m MT7663S \
  -m MT7915E \
  -m RT2X00 \
  -m RT2500USB \
  -m RT73USB \
  -m RT2800USB \
  -m RT2800USB_RT33XX \
  -m RT2800USB_RT35XX \
  -m RT2800USB_RT3573 \
  -m RT2800USB_RT53XX \
  -m RT2800USB_RT55XX

echo "[9] Atheros / Qualcomm WiFi modulba..."
./scripts/config --file .config \
  -m ATH_COMMON \
  -m ATH9K \
  -m ATH9K_HTC \
  -m ATH10K \
  -m ATH10K_PCI \
  -m ATH10K_USB \
  -m ATH10K_SDIO \
  -m ATH11K \
  -m ATH11K_PCI \
  -m ATH11K_AHB

echo "[10] Bluetooth alap driverek modulba..."
./scripts/config --file .config \
  -m BT \
  -m BT_RFCOMM \
  -m BT_BNEP \
  -m BT_HIDP \
  -m BT_HCIBTUSB \
  -m BT_HCIUART \
  -m BT_HCIUART_H4 \
  -m BT_HCIUART_BCM \
  -m BT_HCIUART_RTL \
  -m BT_HCIBTSDIO

echo "[11] Gyakori USB / HID / serial driverek modulba..."
./scripts/config --file .config \
  -m HID \
  -m HID_GENERIC \
  -m USB_HID \
  -m USB_STORAGE \
  -m USB_SERIAL \
  -m USB_SERIAL_CH341 \
  -m USB_SERIAL_CP210X \
  -m USB_SERIAL_FTDI_SIO \
  -m USB_SERIAL_PL2303 \
  -m USB_SERIAL_OPTION

echo "[12] Konfliktusos Broadcom duplikátumok tiltása..."
./scripts/config --file .config \
  -d CYW_BCMDHD \
  -d INFINEON_DHD

echo "[13] olddefconfig..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

echo "[14] Ellenőrző lista:"
grep -iE "COMPILE_TEST|DEBUG_INFO_BTF|RTL8723|RTL8821|RTL8822|BRCM|BCMDHD|MT7601|MT76|ATH10|BT_HCI|USB_SERIAL|MMC_DW_ROCKCHIP" .config || true

echo "Kész."
