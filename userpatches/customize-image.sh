#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot
# The sd card's root path is accessible via $SDCARD variable.

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

Main() {
	case $RELEASE in
		bookworm)

      echo "=== RK3528 custom image beállítások ==="

			export DEBIAN_FRONTEND=noninteractive

			apt-get update
			apt-get install -y \
				openssh-server \
				network-manager \
				wireless-regdb \
				wpasupplicant \
				iw \
				net-tools

			systemctl enable ssh || true
			systemctl enable NetworkManager || true

			echo "=== NetworkManager WiFi powersave tiltás ==="
			mkdir -p /etc/NetworkManager/conf.d
			cat > /etc/NetworkManager/conf.d/wifi-powersave-off.conf <<'EOF'
[connection]
wifi.powersave = 2
EOF

			echo "=== 8733bs driver telepítése ==="
			KVER="5.10.160-legacy-rk3528-tvbox"

			mkdir -p /lib/modules/$KVER/kernel/drivers/net/wireless/rtl8733bs

			if [ -f /tmp/overlay/root/custom-modules/8733bs.ko ]; then
        cp /tmp/overlay/root/custom-modules/8733bs.ko \
           /lib/modules/$KVER/kernel/drivers/net/wireless/rtl8733bs/
			else
				echo "FIGYELEM: /tmp/overlay/root/custom-modules/8733bs.ko nem található!"
			fi

      mkdir -p /lib/modules/$KVER/extra

      if [ -f /tmp/overlay/root/custom-modules/openvfd.ko ]; then
        cp /tmp/overlay/root/custom-modules/openvfd.ko \
           /lib/modules/$KVER/extra/openvfd.ko
      else
        echo "FIGYELEM: /tmp/overlay/root/custom-modules/openvfd.ko nem található!"
      fi

			mkdir -p /etc/modules-load.d
			echo 8733bs > /etc/modules-load.d/8733bs.conf

			depmod -a $KVER || true

      echo "=== Saját DTB telepítése ==="

      mkdir -p /boot/dtb/rockchip

      if [ -f /tmp/overlay/root/custom-dtb/rk3528-vontar-dq08-8733bs-openvfd.dtb ]; then
        cp /tmp/overlay/root/custom-dtb/rk3528-vontar-dq08-8733bs-openvfd.dtb \
           /boot/dtb/rockchip/

        if grep -q "^fdtfile=" /boot/armbianEnv.txt; then
          sed -i \
            's#^fdtfile=.*#fdtfile=rockchip/rk3528-vontar-dq08-8733bs-openvfd.dtb#' \
            /boot/armbianEnv.txt
        else
          echo "fdtfile=rockchip/rk3528-vontar-dq08-8733bs-openvfd.dtb" \
            >> /boot/armbianEnv.txt
        fi
      else
        echo "FIGYELEM: egyedi DTB nem található!"
      fi
      echo "=== OpenVFD konfigurálása ==="

      # OpenVFDService telepítése
      if [ -f /tmp/overlay/root/custom-bin/OpenVFDService ]; then
        cp /tmp/overlay/root/custom-bin/OpenVFDService /usr/bin/OpenVFDService
        chmod +x /usr/bin/OpenVFDService
      else
        echo "FIGYELEM: /tmp/overlay/root/custom-bin/OpenVFDService nem található!"
      fi

      if [ -f /tmp/overlay/root/custom-bin/lcd-mode ]; then
        cp /tmp/overlay/root/custom-bin/lcd-mode /usr/local/bin/lcd-mode
        sed -i 's/\r$//' /usr/local/bin/lcd-mode
        chmod +x /usr/local/bin/lcd-mode
      else
        echo "FIGYELEM: /tmp/overlay/root/custom-bin/lcd-mode nem található!"
      fi

      # OpenVFD végleges DQ08 config
      cat > /etc/openvfd.conf <<'EOF'
vfd_gpio_chip_name='gpio4'
vfd_gpio_clk='0,3,0'
vfd_gpio_dat='0,2,0'
vfd_gpio_stb='0,0,255'

vfd_chars='0,1,2,3,4,0,0'
vfd_dot_bits='4,4,4,4,4,4,4'

vfd_display_type='0,0,0,3'
vfd_brightness='7'
EOF

      # Régi / zavaró LCD kezelők tiltása, amennyire lehet
      cat > /etc/modprobe.d/blacklist-old-lcd.conf <<'EOF'
blacklist lcd_vk2c21
blacklist tm16xx
blacklist tm16xx_display
EOF

      # tm16xx overlay eltávolítása, ha bekerült volna
      sed -i '/^user_overlays=.*rk3528-dq08/d' /boot/armbianEnv.txt || true

      # OpenVFD systemd service
      cat > /etc/systemd/system/openvfd.service <<'EOF'
[Unit]
Description=OpenVFD front LCD service
After=multi-user.target

[Service]
Type=simple
Environment="OPTS=-24h -co 0 1 2 3 4"
ExecStartPre=/bin/sh -c 'lsmod | grep -q "^openvfd " && /usr/sbin/rmmod openvfd || true'
ExecStartPre=/bin/sh -c '. /etc/openvfd.conf; /usr/sbin/modprobe openvfd vfd_gpio_chip_name=$vfd_gpio_chip_name vfd_gpio_clk=$vfd_gpio_clk vfd_gpio_dat=$vfd_gpio_dat vfd_gpio_stb=$vfd_gpio_stb vfd_chars=$vfd_chars vfd_dot_bits=$vfd_dot_bits vfd_display_type=$vfd_display_type vfd_brightness=$vfd_brightness'
ExecStart=/usr/bin/OpenVFDService $OPTS
ExecStop=/usr/bin/killall OpenVFDService
ExecStopPost=/bin/sh -c 'lsmod | grep -q "^openvfd " && /usr/sbin/rmmod openvfd || true'

[Install]
WantedBy=multi-user.target
EOF

      depmod -a $KVER || true
      systemctl daemon-reload || true
      systemctl enable openvfd || true

      echo "=== RTL8733BS Bluetooth konfigurálása ==="

      apt-get install -y bluez rfkill || true

      # Új, RTL8723FS/RTL8733BS-VS kompatibilis rtk_hciattach telepítése
      if [ -f /tmp/overlay/root/custom-bin/rtk_hciattach-new ]; then
        cp /tmp/overlay/root/custom-bin/rtk_hciattach-new /usr/bin/rtk_hciattach-new
        chmod +x /usr/bin/rtk_hciattach-new
      else
        echo "FIGYELEM: rtk_hciattach-new nem található az overlayben!"
      fi

      # Firmware: a régi tool rtl_none_* néven keresi
      mkdir -p /lib/firmware/rtlbt

      if [ -f /tmp/overlay/root/custom-firmware/rtlbt/rtl8723fs_fw ]; then
        cp /tmp/overlay/root/custom-firmware/rtlbt/rtl8723fs_fw /lib/firmware/rtlbt/rtl_none_fw
      else
        echo "FIGYELEM: rtl8723fs_fw nem található!"
      fi

      if [ -f /tmp/overlay/root/custom-firmware/rtlbt/rtl8723fs_config ]; then
        cp /tmp/overlay/root/custom-firmware/rtlbt/rtl8723fs_config /lib/firmware/rtlbt/rtl_none_config
      else
        echo "FIGYELEM: rtl8723fs_config nem található!"
      fi

      # Bluetooth automatikus indítás
      cat > /etc/systemd/system/rtl8733bs-bt.service <<'EOF'
[Unit]
Description=RTL8733BS Bluetooth H5 attach
Before=bluetooth.service
Wants=bluetooth.service
After=multi-user.target

[Service]
Type=simple
ExecStartPre=/usr/sbin/rfkill unblock bluetooth
ExecStart=/usr/bin/rtk_hciattach-new -n -s 115200 /dev/ttyS2 rtk_h5
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

      systemctl daemon-reload || true
      systemctl enable rtl8733bs-bt.service || true
      systemctl enable bluetooth.service || true

      echo "=== Home Assistant telepítő előkészítése ==="

      mkdir -p /root/ha-packages

      if [ -d /tmp/overlay/root/ha-packages ]; then
        cp -a /tmp/overlay/root/ha-packages/* /root/ha-packages/ || true
      else
        echo "FIGYELEM: /tmp/overlay/root/ha-packages nem található!"
      fi

      if [ -f /tmp/overlay/root/custom-bin/install-ha ]; then
        cp /tmp/overlay/root/custom-bin/install-ha /usr/local/bin/install-ha
        sed -i 's/\r$//' /usr/local/bin/install-ha
        chmod +x /usr/local/bin/install-ha
      else
        echo "FIGYELEM: install-ha nem található az overlayben!"
      fi

			;;
		stretch|buster|bullseye|bionic|focal)
			;;
	esac
} # Main

InstallOpenMediaVault() {
	# use this routine to create a Debian based fully functional OpenMediaVault
	# image (OMV 3 on Jessie, OMV 4 with Stretch). Use of mainline kernel highly
	# recommended!
	#
	# Please note that this variant changes Armbian default security 
	# policies since you end up with root password 'openmediavault' which
	# you have to change yourself later. SSH login as root has to be enabled
	# through OMV web UI first
	#
	# This routine is based on idea/code courtesy Benny Stark. For fixes,
	# discussion and feature requests please refer to
	# https://forum.armbian.com/index.php?/topic/2644-openmediavault-3x-customize-imagesh/

	echo root:openmediavault | chpasswd
	rm /root/.not_logged_in_yet
	. /etc/default/cpufrequtils
	export LANG=C LC_ALL="en_US.UTF-8"
	export DEBIAN_FRONTEND=noninteractive
	export APT_LISTCHANGES_FRONTEND=none

	case ${RELEASE} in
		jessie)
			OMV_Name="erasmus"
			OMV_EXTRAS_URL="https://github.com/OpenMediaVault-Plugin-Developers/packages/raw/master/openmediavault-omvextrasorg_latest_all3.deb"
			;;
		stretch)
			OMV_Name="arrakis"
			OMV_EXTRAS_URL="https://github.com/OpenMediaVault-Plugin-Developers/packages/raw/master/openmediavault-omvextrasorg_latest_all4.deb"
			;;
	esac

	# Add OMV source.list and Update System
	cat > /etc/apt/sources.list.d/openmediavault.list <<- EOF
	deb https://openmediavault.github.io/packages/ ${OMV_Name} main
	## Uncomment the following line to add software from the proposed repository.
	deb https://openmediavault.github.io/packages/ ${OMV_Name}-proposed main
	
	## This software is not part of OpenMediaVault, but is offered by third-party
	## developers as a service to OpenMediaVault users.
	# deb https://openmediavault.github.io/packages/ ${OMV_Name} partner
	EOF

	# Add OMV and OMV Plugin developer keys, add Cloudshell 2 repo for XU4
	if [ "${BOARD}" = "odroidxu4" ]; then
		add-apt-repository -y ppa:kyle1117/ppa
		sed -i 's/jessie/xenial/' /etc/apt/sources.list.d/kyle1117-ppa-jessie.list
	fi
	mount --bind /dev/null /proc/mdstat
	apt-get update
	apt-get --yes --force-yes --allow-unauthenticated install openmediavault-keyring
	apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 7AA630A1EDEE7D73
	apt-get update

	# install debconf-utils, postfix and OMV
	HOSTNAME="${BOARD}"
	debconf-set-selections <<< "postfix postfix/mailname string ${HOSTNAME}"
	debconf-set-selections <<< "postfix postfix/main_mailer_type string 'No configuration'"
	apt-get --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends \
		-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install \
		debconf-utils postfix
	# move newaliases temporarely out of the way (see Ubuntu bug 1531299)
	cp -p /usr/bin/newaliases /usr/bin/newaliases.bak && ln -sf /bin/true /usr/bin/newaliases
	sed -i -e "s/^::1         localhost.*/::1         ${HOSTNAME} localhost ip6-localhost ip6-loopback/" \
		-e "s/^127.0.0.1   localhost.*/127.0.0.1   ${HOSTNAME} localhost/" /etc/hosts
	sed -i -e "s/^mydestination =.*/mydestination = ${HOSTNAME}, localhost.localdomain, localhost/" \
		-e "s/^myhostname =.*/myhostname = ${HOSTNAME}/" /etc/postfix/main.cf
	apt-get --yes --force-yes --allow-unauthenticated  --fix-missing --no-install-recommends \
		-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install \
		openmediavault

	# install OMV extras, enable folder2ram and tweak some settings
	FILE=$(mktemp)
	curl "$OMV_EXTRAS_URL" -fLso "$FILE" && dpkg -i "$FILE"
	
	/usr/sbin/omv-update
	# Install flashmemory plugin and netatalk by default, use nice logo for the latter,
	# tweak some OMV settings
	. /usr/share/openmediavault/scripts/helper-functions
	apt-get -y -q install openmediavault-netatalk openmediavault-flashmemory
	AFP_Options="mimic model = Macmini"
	SMB_Options="min receivefile size = 16384\nwrite cache size = 524288\ngetwd cache = yes\nsocket options = TCP_NODELAY IPTOS_LOWDELAY"
	xmlstarlet ed -L -u "/config/services/afp/extraoptions" -v "$(echo -e "${AFP_Options}")" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/smb/extraoptions" -v "$(echo -e "${SMB_Options}")" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/flashmemory/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/ssh/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/services/ssh/permitrootlogin" -v "0" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/time/ntp/enable" -v "1" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/time/timezone" -v "UTC" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/network/dns/hostname" -v "${HOSTNAME}" /etc/openmediavault/config.xml
	xmlstarlet ed -L -u "/config/system/monitoring/perfstats/enable" -v "0" /etc/openmediavault/config.xml
	echo -e "OMV_CPUFREQUTILS_GOVERNOR=${GOVERNOR}" >>/etc/default/openmediavault
	echo -e "OMV_CPUFREQUTILS_MINSPEED=${MIN_SPEED}" >>/etc/default/openmediavault
	echo -e "OMV_CPUFREQUTILS_MAXSPEED=${MAX_SPEED}" >>/etc/default/openmediavault
	for i in netatalk samba flashmemory ssh ntp timezone interfaces cpufrequtils monit collectd rrdcached ; do
		/usr/sbin/omv-mkconf $i
	done
	/sbin/folder2ram -enablesystemd || true
	sed -i 's|-j /var/lib/rrdcached/journal/ ||' /etc/init.d/rrdcached

	# Fix multiple sources entry on ARM with OMV4
	sed -i '/stretch-backports/d' /etc/apt/sources.list

	# rootfs resize to 7.3G max and adding omv-initsystem to firstrun -- q&d but shouldn't matter
	echo 15500000s >/root/.rootfs_resize
	sed -i '/systemctl\ disable\ armbian-firstrun/i \
	mv /usr/bin/newaliases.bak /usr/bin/newaliases \
	export DEBIAN_FRONTEND=noninteractive \
	sleep 3 \
	apt-get install -f -qq python-pip python-setuptools || exit 0 \
	pip install -U tzupdate \
	tzupdate \
	read TZ </etc/timezone \
	/usr/sbin/omv-initsystem \
	xmlstarlet ed -L -u "/config/system/time/timezone" -v "${TZ}" /etc/openmediavault/config.xml \
	/usr/sbin/omv-mkconf timezone \
	lsusb | egrep -q "0b95:1790|0b95:178a|0df6:0072" || sed -i "/ax88179_178a/d" /etc/modules' /usr/lib/armbian/armbian-firstrun
	sed -i '/systemctl\ disable\ armbian-firstrun/a \
	sleep 30 && sync && reboot' /usr/lib/armbian/armbian-firstrun

	# add USB3 Gigabit Ethernet support
	echo -e "r8152\nax88179_178a" >>/etc/modules

	# Special treatment for ODROID-XU4 (and later Amlogic S912, RK3399 and other big.LITTLE
	# based devices). Move all NAS daemons to the big cores. With ODROID-XU4 a lot
	# more tweaks are needed. CS2 repo added, CS1 workaround added, coherent_pool=1M
	# set: https://forum.odroid.com/viewtopic.php?f=146&t=26016&start=200#p197729
	# (latter not necessary any more since we fixed it upstream in Armbian)
	case ${BOARD} in
		odroidxu4)
			HMP_Fix='; taskset -c -p 4-7 $i '
			# Cloudshell stuff (fan, lcd, missing serials on 1st CS2 batch)
			echo "H4sIAKdXHVkCA7WQXWuDMBiFr+eveOe6FcbSrEIH3WihWx0rtVbUFQqCqAkYGhJn
			tF1x/vep+7oebDfh5DmHwJOzUxwzgeNIpRp9zWRegDPznya4VDlWTXXbpS58XJtD
			i7ICmFBFxDmgI6AXSLgsiUop54gnBC40rkoVA9rDG0SHHaBHPQx16GN3Zs/XqxBD
			leVMFNAz6n6zSWlEAIlhEw8p4xTyFtwBkdoJTVIJ+sz3Xa9iZEMFkXk9mQT6cGSQ
			QL+Cr8rJJSmTouuuRzfDtluarm1aLVHksgWmvanm5sbfOmY3JEztWu5tV9bCXn4S
			HB8RIzjoUbGvFvPw/tmr0UMr6bWSBupVrulY2xp9T1bruWnVga7DdAqYFgkuCd3j
			vORUDQgej9HPJxmDDv+3WxblBSuYFH8oiNpHz8XvPIkU9B3JVCJ/awIAAA==" \
			| tr -d '[:blank:]' | base64 --decode | gunzip -c >/usr/local/sbin/cloudshell2-support.sh
			chmod 755 /usr/local/sbin/cloudshell2-support.sh
			apt install -y i2c-tools odroid-cloudshell cloudshell2-fan
			sed -i '/systemctl\ disable\ armbian-firstrun/i \
			lsusb | grep -q -i "05e3:0735" && sed -i "/exit\ 0/i echo 20 > /sys/class/block/sda/queue/max_sectors_kb" /etc/rc.local \
			/usr/sbin/i2cdetect -y 1 | grep -q "60: 60" && /usr/local/sbin/cloudshell2-support.sh' /usr/lib/armbian/armbian-firstrun
			;;
		bananapim3)
			HMP_Fix='; taskset -c -p 4-7 $i '
			;;
		edge*|ficus|firefly-rk3399|nanopct4|nanopim4|nanopineo4|renegade-elite|roc-rk3399-pc|rockpro64|station-p1)
			HMP_Fix='; taskset -c -p 4-5 $i '
			;;
	esac
	echo "* * * * * root for i in \`pgrep \"ftpd|nfsiod|smbd|afpd|cnid\"\` ; do ionice -c1 -p \$i ${HMP_Fix}; done >/dev/null 2>&1" \
		>/etc/cron.d/make_nas_processes_faster
	chmod 600 /etc/cron.d/make_nas_processes_faster

	# add SATA port multiplier hint if appropriate
	[ "${LINUXFAMILY}" = "sunxi" ] && \
		echo -e "#\n# If you want to use a SATA PM add \"ahci_sunxi.enable_pmp=1\" to bootargs above" \
		>>/boot/boot.cmd

	# Filter out some log messages
	echo ':msg, contains, "do ionice -c1" ~' >/etc/rsyslog.d/omv-armbian.conf
	echo ':msg, contains, "action " ~' >>/etc/rsyslog.d/omv-armbian.conf
	echo ':msg, contains, "netsnmp_assert" ~' >>/etc/rsyslog.d/omv-armbian.conf
	echo ':msg, contains, "Failed to initiate sched scan" ~' >>/etc/rsyslog.d/omv-armbian.conf

	# Fix little python bug upstream Debian 9 obviously ignores
	if [ -f /usr/lib/python3.5/weakref.py ]; then
		GITREF="9cd7e17640a49635d1c1f8c2989578a8fc2c1de6"
		curl -fLo /usr/lib/python3.5/weakref.py \
			"https://raw.githubusercontent.com/python/cpython/${GITREF}/Lib/weakref.py"
	fi

	# clean up and force password change on first boot
	umount /proc/mdstat
	chage -d 0 root
} # InstallOpenMediaVault

UnattendedStorageBenchmark() {
	# Function to create Armbian images ready for unattended storage performance testing.
	# Useful to use the same OS image with a bunch of different SD cards or eMMC modules
	# to test for performance differences without wasting too much time.

	rm /root/.not_logged_in_yet

	apt-get -qq install time

	curl -fLso /usr/local/bin/sd-card-bench.sh "https://raw.githubusercontent.com/ThomasKaiser/sbc-bench/master/sd-card-bench.sh"
	chmod 755 /usr/local/bin/sd-card-bench.sh

	sed -i '/^exit\ 0$/i \
	/usr/local/bin/sd-card-bench.sh &' /etc/rc.local
} # UnattendedStorageBenchmark

InstallAdvancedDesktop()
{
	apt-get install -yy transmission libreoffice libreoffice-style-tango meld remmina thunderbird kazam avahi-daemon
	[[ -f /usr/share/doc/avahi-daemon/examples/sftp-ssh.service ]] && cp /usr/share/doc/avahi-daemon/examples/sftp-ssh.service /etc/avahi/services/
	[[ -f /usr/share/doc/avahi-daemon/examples/ssh.service ]] && cp /usr/share/doc/avahi-daemon/examples/ssh.service /etc/avahi/services/
	apt clean
} # InstallAdvancedDesktop

Main "$@"
