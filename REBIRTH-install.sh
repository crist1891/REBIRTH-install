#!/bin/bash

# Exit on any error
set -e

# Check if the system is booted in EFI mode
if [ ! -d "/sys/firmware/efi/efivars" ]; then
    echo "Error: System is not booted in EFI mode. Please boot in EFI mode and try again."
    exit 1
fi

# Set variables for partitions
EFI_PARTITION="/dev/nvme0n1p1"
SWAP_PARTITION="/dev/nvme0n1p2"
ROOT_PARTITION="/dev/nvme0n1p3"

# Update system clock
timedatectl set-ntp true

# Format the partitions
mkfs.fat -F32 $EFI_PARTITION
mkswap $SWAP_PARTITION
swapon $SWAP_PARTITION
mkfs.ext4 $ROOT_PARTITION

# Mount the root partition
mount $ROOT_PARTITION /mnt

# Create and mount the EFI partition
mkdir -p /mnt/boot/efi
mount $EFI_PARTITION /mnt/boot/efi

# Install essential packages
pacstrap /mnt base linux linux-firmware

# Generate an fstab file
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF

# Set up timezone
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc

# Configure localization
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set up hostname
echo "REBIRTH-7" > /etc/hostname
cat << HOSTS > /etc/hosts
127.0.0.1    localhost
::1          localhost
127.0.1.1    REBIRTH-7.localdomain REBIRTH-7
HOSTS

# Set root password
echo root:123 | chpasswd

# Enable multilib in pacman
sed -i '/#\[multilib\]/s/^#//g' /etc/pacman.conf
sed -i '/#Include = \/etc\/pacman.d\/mirrorlist/s/^#//g' /etc/pacman.conf
pacman -Sy

# Install necessary packages for networking, grub, and Hyperland setup
pacman -S --noconfirm grub efibootmgr networkmanager network-manager-applet \
  dialog wpa_supplicant mtools dosfstools base-devel linux-headers \
  avahi xdg-user-dirs xdg-utils gvfs gvfs-smb nfs-utils inetutils dnsutils \
  bash-completion openssh rsync reflector acpi acpi_call iptables-nft ipset \
  firewalld sof-firmware nss-mdns acpid os-prober ntfs-3g amd-ucode

# Enable NetworkManager
systemctl enable NetworkManager

# Install and configure GRUB with os-prober
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Create a user with additional groups and /bin/bash as the shell
useradd -mG wheel,storage,power -s /bin/bash cristian
echo cristian:123 | chpasswd

# Uncomment wheel group in sudoers for privilege escalation
sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^# //g' /etc/sudoers

# Install Hyperland and other user applications
pacman -S --noconfirm sway waybar hyperland-git wlroots xorg-xwayland \
  alacritty wl-clipboard grim slurp swaybg swaylock wayfire wayfire-plugins \
  wofi dmenu firefox nano mesa vulkan-radeon steam

# Configure initial Hyperland session
mkdir -p /home/cristian/.config/hyperland
cp -r /etc/hyperland/* /home/cristian/.config/hyperland/
chown -R cristian:cristian /home/cristian/.config/hyperland

EOF

echo "Installation complete replace root and user password"

