#! /bin/bash

# Script declarations
pxe_data_path='/var/lib/PXE'
images_path="$pxe_data_path/images"
livecd_extract_path="$pxe_data_path/extract-livecd"
livecd_image_name='ubuntu-20.04-desktop-amd64.iso'
livecd_dist_name="OB_modded"
livecd_title_name="OB modded"
tftp_path='/var/lib/tftpboot'
working_dir="$pxe_data_path/working_dir"

# Extract the LiveCD OS
apt install -y genisoimage squashfs-tools xorriso

mkdir {$livecd_extract_path,$working_dir}
cd $working_dir

if [ ! -f $images_path/$livecd_image_name ]; then
    echo -e "Error as occured -- $images_path/$livecd_image_name does not exists"
    exit 1
fi

mount $images_path/$livecd_image_name $pxe_data_path/tmp
rsync --exclude=/casper/filesystem.squashfs -a $pxe_data_path/tmp/ $livecd_extract_path

# Prepare & Chroot
unsquashfs $pxe_data_path/tmp/casper/filesystem.squashfs
mv squashfs-root edit
mount -o bind /run/ edit/run
mount --bind /dev/ edit/dev
chroot edit
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts
export HOME=/root
export LC_ALL=C

#### Chroot env. variables
virtual_machine='False'
####

# Packages management
echo -e "\n\ndeb http://archive.ubuntu.com/ubuntu focal universe\ndeb http://archive.ubuntu.com/ubuntu focal-updates universe\ndeb http://archive.ubuntu.com/ubuntu focal-security universe" >> /etc/apt/sources.list
apt update
dpkg-divert --local --rename --add /sbin/initctl
ln -s /bin/true /sbin/initctl

apt purge -y apparmor apparmor-utils gnome-todo hyphen-ru libjuh-java libjurt-java libreoffice-common libreoffice-style-breeze libreoffice-style-colibre libreoffice-style-elementary \
libreoffice-style-tango librhythmbox-core10 libridl-java libuno-cppu3 libuno-cppuhelpergcc3-3 libuno-purpenvhelpergcc3-3 libuno-sal3 libuno-salhelpergcc3-3 \
libunoloader-java mythes-de mythes-de-ch mythes-en-us mythes-es mythes-fr mythes-it mythes-pt-pt mythes-ru rhythmbox rhythmbox-data thunderbird

apt install -y alien conky curl exfat-fuse exfat-utils glances ipmitool libncurses5 lldpd mdadm net-tools nfs-common openssh-server screen smartmontools traceroute vim
if [[ $virtual_machine == 'True' ]]; then 
    apt install -y open-vm-tools
fi

# SSHD configuration
rm /etc/ssh/sshd_config
cat >> /etc/ssh/sshd_config << EOF
# OpenSSH-Server Live configuration

AcceptEnv LANG LC_*
ChallengeResponseAuthentication no
Include /etc/ssh/sshd_config.d/*.conf
PasswordAuthentication yes
PermitEmptyPasswords yes
PrintMotd yes
Subsystem       sftp    /usr/lib/openssh/sftp-server
UsePAM yes
X11Forwarding yes
EOF

# MegaCLI
wget https://docs.broadcom.com/docs-and-downloads/raid-controllers/raid-controllers-common-files/8-07-14_MegaCLI.zip -P /tmp/
unzip /tmp/8-07-14_MegaCLI.zip -d /tmp
alien /tmp/Linux/MegaCli-8.07.14-1.noarch.rpm
dpkg -i megacli_8.07.14-2_all.deb
rm -f megacli_8.07.14-2_all.deb
ln -s /opt/MegaRAID/MegaCli/MegaCli64 /usr/bin/megacli

# Conky configuration
### Provide AutomatiK Conky from a repo  -- https://www.gnome-look.org/p/1170490/ ###
### Temporary code ###
wget https://github.com/Devorkin/Ubuntu-PXE---Custom-LiveCD/raw/main/automatik.zip -P /tmp/
unzip /tmp/automatik.zip -d /tmp
mkdir /usr/local/lib/conky
###
mv /tmp/AutomatiK /usr/local/lib/conky/
chown -R 999:999 /usr/local/lib/conky/AutomatiK
cat >> /etc/xdg/autostart/conky.desktop << EOF
[Desktop Entry]
Type=Application
Name=ConkyLauncher
Exec=/usr/local/lib/conky/AutomatiK/start.sh
OnlyShowIn=GNOME;
EOF

# Other OS changes
ufw disable

# Cleaup process
apt upgrade -y
apt autoremove -y
apt clean
rm -rf /tmp/* ~/.bash_history /etc/resolv.conf
rm /sbin/initctl
dpkg-divert --rename --remove /sbin/initctl
umount /proc || umount -lf /proc
umount /sys
umount /dev/pts
umount /dev
# IF umount of /dev fails, restart the host system
exit

# Producing the CD image
chmod +w $livecd_extract_path/casper/filesystem.manifest
chroot edit dpkg-query -W --showformat='${Package} ${Version}\n' > $livecd_extract_path/casper/filesystem.manifest
cp $livecd_extract_path/casper/filesystem.manifest $livecd_extract_path/casper/filesystem.manifest-desktop
sed -i '/ubiquity/d' $livecd_extract_path/casper/filesystem.manifest-desktop
sed -i '/casper/d' $livecd_extract_path/casper/filesystem.manifest-desktop

if [ -f $livecd_extract_path/casper/filesystem.squashfs ]; then rm $livecd_extract_path/casper/filesystem.squashfs; fi
mksquashfs edit $livecd_extract_path/casper/filesystem.squashfs -b 1048576
printf $(du -sx --block-size=1 edit | cut -f1) > $livecd_extract_path/casper/filesystem.size
original_disk_name=$(cat $livecd_extract_path/README.diskdefines | grep DISKNAME | sed -e 's/#define DISKNAME  //')
sed -i "s|#define DISKNAME  $original_disk_name|#define DISKNAME  Ubuntu 20.04 -- ${livecd_title_name}|" $livecd_extract_path/README.diskdefines

cd $livecd_extract_path
rm md5sum.txt
find -type f -print0 | xargs -0 md5sum | grep -v isolinux/boot.cat | tee md5sum.txt

mkisofs -D -r -V "Ubuntu_custom" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $images_path/ubuntu-${livecd_dist_name}.iso .

umount $pxe_data_path/tmp
umount $working_dir/edit/run

mkdir $pxe_data_path/data/ubuntu-${livecd_dist_name}
mount $images_path/ubuntu-${livecd_dist_name}.iso $pxe_data_path/tmp
cp -r $pxe_data_path/tmp/* $pxe_data_path/data/ubuntu-${livecd_dist_name}/
cp -r $pxe_data_path/tmp/.disk $pxe_data_path/data/ubuntu-${livecd_dist_name}/
umount $pxe_data_path/tmp

line_num=`expr $(grep ^LABEL /var/lib/tftpboot/pxelinux.cfg/default | awk '{print $2}' | tail -n 1) + 1`
cat >> $tftp_path/pxelinux.cfg/default << EOF
LABEL $line_num
  MENU LABEL Ubuntu -- 20.04 - ${livecd_title_name}, from NFS
  KERNEL vmlinuz-20.04-desktop
  APPEND initrd=initrd-20.04-desktop nfsroot=10.10.20.2:/var/lib/PXE/data/ubuntu-${livecd_dist_name} ro netboot=nfs boot=casper ip=dhcp ---

EOF
