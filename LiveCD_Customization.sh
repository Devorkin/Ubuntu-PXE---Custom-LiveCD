#! /bin/bash

# Script declarations
pxe_data_path='/var/lib/PXE'
images_path="$pxe_data_path/images"
livecd_extract_path="$pxe_data_path/extract-livecd"
working_dir="$pxe_data_path/working_dir"

# Extract the LiveCD OS
apt install -y squashfs-tools xorriso

mkdir {$livecd_extract_path,$working_dir}
cd $working_dir

mount $images_path/ubuntu-20.04-desktop-amd64.iso $pxe_data_path/tmp
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

# Add user account
# pxe_ssh_user_account='pxeuser'
# pxe_ssh_user_passwd='Qwer123$'
# encrypted_passwd=$(perl -e 'print crypt($ARGV[0], "password")' $pxe_ssh_user_passwd)
# useradd -m -u 2000 -s /bin/bash -p $encrypted_passwd -U $pxe_ssh_user_account

# Install packages
echo -e "\n\ndeb http://archive.ubuntu.com/ubuntu focal universe\ndeb http://archive.ubuntu.com/ubuntu focal-updates universe\ndeb http://archive.ubuntu.com/ubuntu focal-security universe" >> /etc/apt/sources.list
apt update
dpkg-divert --local --rename --add /sbin/initctl
ln -s /bin/true /sbin/initctl
apt install -y conky curl exfat-fuse exfat-utils glances lldpd mdadm net-tools nfs-common openssh-server screen smartmontools traceroute vim

# For VM image
# apt install -y open-vm-tools

# Remove packages
apt purge -y apparmor apparmor-utils gnome-todo hyphen-ru libjuh-java libjurt-java libreoffice-common libreoffice-style-breeze libreoffice-style-colibre libreoffice-style-elementary \
libreoffice-style-tango librhythmbox-core10 libridl-java libuno-cppu3 libuno-cppuhelpergcc3-3 libuno-purpenvhelpergcc3-3 libuno-sal3 libuno-salhelpergcc3-3 \
libunoloader-java mythes-de mythes-de-ch mythes-en-us mythes-es mythes-fr mythes-it mythes-pt-pt mythes-ru rhythmbox rhythmbox-data thunderbird

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

# Conky configuration
### Provide AutomatiK Conky from a repo  -- https://www.gnome-look.org/p/1170490/ ###
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

rm $livecd_extract_path/casper/filesystem.squashfs
mksquashfs edit $livecd_extract_path/casper/filesystem.squashfs -b 1048576
printf $(du -sx --block-size=1 edit | cut -f1) > $livecd_extract_path/casper/filesystem.size
original_disk_name=$(cat $livecd_extract_path/README.diskdefines | grep DISKNAME | sed -e 's/#define DISKNAME  //')
sed -i "s|#define DISKNAME  $original_disk_name|#define DISKNAME  Ubuntu 20.04 -- Devorkin.net ed.|" $livecd_extract_path/README.diskdefines

cd $livecd_extract_path
rm md5sum.txt
find -type f -print0 | sudo xargs -0 md5sum | grep -v isolinux/boot.cat | sudo tee md5sum.txt

mkisofs -D -r -V "Ubuntu_custom" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $images_path/ubuntu-20.04-desktop-amd64-custom.iso .

umount $pxe_data_path/tmp
umount $working_dir/edit/run
