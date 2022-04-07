#! /bin/bash

# Script declarations
pxe_data_path='/var/lib/PXE'
images_path="$pxe_data_path/images"
livecd_dist_name='20.04-desktop'
livecd_image_name='ubuntu-20.04-desktop-amd64.iso'
netplan_configuration_file='/etc/netplan/00-installer-config.yaml'
tftp_path='/var/lib/tftpboot'

# Run as Root
apt update; apt upgrade -y
apt install -y isc-dhcp-server net-tools nfs-kernel-server screen syslinux-common tcpdump tftpd-hpa vim wget

# Configure network interface
mgmt_interface="$(ip a | egrep '^[0-9]:' | sed '2!d' | tr -s ' ' | sed 's/ /:/g' | cut -d ':' -f3)"
dhcp_interface="$(ip a | egrep '^[0-9]:' | sed '3!d' | tr -s ' ' | sed 's/ /:/g' | cut -d ':' -f3)"
mv $netplan_configuration_file ${netplan_configuration_file}.conf_original
cat >> $netplan_configuration_file << EOF
# This is the network config written by "Kickstart project script"
network:
  ethernets:
    $mgmt_interface:
      dhcp4: true
    $dhcp_interface:
      dhcp4: no
      addresses:
        - 10.10.20.2/24
  version: 2
EOF
netplan apply

# DHCPD configuration
systemctl enable isc-dhcp-server
sed -i "s|INTERFACESv4=\"\"|INTERFACESv4=\"$dhcp_interface\"|" /etc/default/isc-dhcp-server

mv /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf_original
cat >> /etc/dhcp/dhcpd.conf << EOF
default-lease-time 604800;
max-lease-time 2592000;

subnet 10.10.20.0 netmask 255.255.255.0 {
  option broadcast-address        10.10.20.255;
  option domain-name              "test.net";
  option routers                  10.10.20.2;
  option subnet-mask              255.255.255.0;
  pool {
    range                         10.10.20.30 10.10.20.254;
  }
}

allow booting;
allow bootp;
filename "pxelinux.0";
next-server 10.10.20.2;

EOF
systemctl restart isc-dhcp-server

# TFTP server configuration
mkdir $tftp_path
sed -i "s|TFTP_DIRECTORY=\"/srv/tftp\"|TFTP_DIRECTORY=\"$tftp_path\"|" /etc/default/tftpd-hpa
systemctl restart tftpd-hpa

# PXE configuration
wget http://archive.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/pxelinux.0 -P $tftp_path/
cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libutil.c32,menu.c32} $tftp_path/
mkdir $tftp_path/pxelinux.cfg

if [[ -f $tftp_path/pxelinux.cfg/default ]]; then rm -f $tftp_path/pxelinux.cfg/default; fi
cat >> $tftp_path/pxelinux.cfg/default << EOF
DEFAULT menu.c32
PROMPT  0
TIMEOUT 100
ONTIMEOUT local
MENU TITLE ##### PXE Lab Project #####

LABEL local
  MENU LABEL Local -- Boot from local disk
  localboot 0
  
LABEL 1
  MENU LABEL Ubuntu -- 20.04 - LiveCD, from the Internet
  KERNEL vmlinuz-20.04-desktop
  INITRD initrd-20.04-desktop
  APPEND root=/dev/ram0 ramdisk_size=1500000 ip=dhcp url=http://cdimage.ubuntu.com/ubuntu-server/daily-live/current/focal-live-server-amd64.iso

LABEL 2
  MENU LABEL Ubuntu -- 20.04 - LiveCD, from NFS
  KERNEL vmlinuz-20.04-desktop
  APPEND initrd=initrd-20.04-desktop nfsroot=10.10.20.2:/var/lib/PXE/data/ubuntu-${livecd_dist_name} ro netboot=nfs boot=casper ip=dhcp ---

EOF

# Installations preparation
mkdir -p $pxe_data_path/{data,images,tmp}
wget http://ubuntu.interhost.co.il/focal/$livecd_image_name -P $images_path/

mkdir $pxe_data_path/data/ubuntu-${livecd_dist_name}
mount $images_path/$livecd_image_name $pxe_data_path/tmp
cp -r $pxe_data_path/tmp/* $pxe_data_path/data/ubuntu-${livecd_dist_name}/
cp -r $pxe_data_path/tmp/.disk $pxe_data_path/data/ubuntu-${livecd_dist_name}/
umount $pxe_data_path/tmp
cp $pxe_data_path/data/ubuntu-${livecd_dist_name}/casper/initrd $tftp_path/initrd-20.04-desktop
cp $pxe_data_path/data/ubuntu-${livecd_dist_name}/casper/vmlinuz $tftp_path/vmlinuz-20.04-desktop

# NFS:
echo -e "\n# PXE share\n/var/lib/PXE/data\t10.10.20.0/24\t(ro,sync,no_root_squash)" >> /etc/exports
systemctl restart nfs-server

echo -e "\n###########################################################################"
echo -e "\tDHCPD service is configured and ready"
echo -e "\tPXE service is configured and ready"
echo -e "\t\t - Ubuntu 20.04 Live CD from the Internet is configured"
echo -e "\t\t - Ubuntu 20.04 Live CD from NFS share is configured"
echo -e "\tEnjoy!"
echo -e "###########################################################################\n"
