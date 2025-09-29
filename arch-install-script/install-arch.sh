#!/bin/bash

# Script de instalación de Arch Linux
# IMPORTANTE: Ejecutar desde el live environment de Arch

set -e  # Detener el script en caso de error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para imprimir mensajes
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar si estamos en el live environment
if ! grep -q "Arch Linux" /etc/os-release 2>/dev/null; then
    print_error "Este script debe ejecutarse desde el live environment de Arch Linux"
    exit 1
fi

# Verificar conexión a internet
print_message "Verificando conexión a internet..."
if ! ping -c 1 archlinux.org &> /dev/null; then
    print_error "No hay conexión a internet. Configura la red primero."
    exit 1
fi

# Mostrar discos disponibles
print_message "Discos disponibles:"
lsblk

# Variables de configuración (MODIFICA ESTAS SEGÚN TUS NECESIDADES)
DISK="/dev/sda"
HOSTNAME="arch"
USERNAME="ramdonx"
USER_PASSWORD="1549"
ROOT_PASSWORD="Xi1aTWx2"
TIMEZONE="America/Bogota"  # Timezone para Colombia
KEYMAP="us"

# Confirmación antes de continuar
print_warning "Este script formateará el disco: $DISK"
print_warning "Se crearán las siguientes particiones:"
print_warning "sda1: 2G /boot"
print_warning "sda2: 40G /"
print_warning "sda3: 69.8G /home"
print_warning "¿Continuar? (s/N)"
read -r confirmation
if [[ ! $confirmation =~ ^[Ss]$ ]]; then
    print_message "Instalación cancelada."
    exit 0
fi

# Configurar mirrors más rápidos para Colombia
print_message "Configurando mirrors para Colombia..."
cat > /etc/pacman.d/mirrorlist << MIRRORS
## Colombia
Server = https://mirrors.unal.edu.co/archlinux/\$repo/os/\$arch
Server = http://mirrors.unal.edu.co/archlinux/\$repo/os/\$arch
Server = https://mirror.ufps.edu.co/archlinux/\$repo/os/\$arch
Server = http://mirror.ufps.edu.co/archlinux/\$repo/os/\$arch
## Global mirrors
Server = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch
MIRRORS

# Sincronizar hora
print_message "Sincronizando hora..."
timedatectl set-ntp true

# Particionado según estructura especificada
print_message "Creando particiones..."
# Limpiar tabla de particiones existente
wipefs -a "$DISK"

# Crear tabla de particiones GPT
parted -s "$DISK" mklabel gpt

# Crear particiones
# sda1: 2G para /boot
parted -s "$DISK" mkpart "boot" fat32 1MiB 2GiB
parted -s "$DISK" set 1 esp on

# sda2: 40G para /
parted -s "$DISK" mkpart "root" ext4 2GiB 42GiB

# sda3: 69.8G para /home
parted -s "$DISK" mkpart "home" ext4 42GiB 111.8GiB

# Formatear particiones
print_message "Formateando particiones..."
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"
mkfs.ext4 "${DISK}3"

# Montar particiones
print_message "Montando particiones..."
mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mkdir -p /mnt/home
mount "${DISK}1" /mnt/boot
mount "${DISK}3" /mnt/home

# Configurar pacman para multilib y extra
print_message "Configurando repositorios multilib y extra..."
cat > /etc/pacman.conf << PACMANCONF
[options]
HoldPkg     = pacman glibc
Architecture = auto

# Colombia mirrors
Include = /etc/pacman.d/mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[community]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist

# Agregar repositorio multilib-testing si se desea
#[multilib-testing]
#Include = /etc/pacman.d/mirrorlist

# Configuraciones adicionales
Color
ILoveCandy
CheckSpace
VerbosePkgLists
ParallelDownloads = 5
PACMANCONF

# Actualizar base de datos de paquetes
print_message "Actualizando base de datos de paquetes..."
pacman -Syy

# Instalar sistema base con kernel Zen
print_message "Instalando sistema base con kernel Zen..."
pacstrap /mnt base base-devel linux-zen linux-zen-headers linux-firmware

# Generar fstab en /mnt/etc/fstab
print_message "Generando fstab en /mnt/etc/fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Configuración del sistema
print_message "Configurando sistema..."

# Script para chroot
arch-chroot /mnt /bin/bash <<EOF
# Configurar timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Configurar locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "es_MX.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Configurar teclado
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Configurar hostname
echo "$HOSTNAME" > /etc/hostname

# Configurar hosts
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Configurar contraseñas
echo "root:$ROOT_PASSWORD" | chpasswd

# Crear usuario
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Configurar sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Instalar paquetes necesarios para GRUB y sistema
pacman -S --noconfirm grub efibootmgr dosfstools mtools

# Instalar y configurar bootloader
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Instalar paquetes adicionales básicos
pacman -S --noconfirm networkmanager sudo vim git

# Habilitar servicios
systemctl enable NetworkManager

# Verificar instalación del kernel
print_message "Kernel instalado:"
ls /boot/vmlinuz*

# Configurar mirrors en el sistema instalado
cat > /etc/pacman.d/mirrorlist <<MIRRORS_INSTALLED
## Colombia
Server = https://mirrors.unal.edu.co/archlinux/\$repo/os/\$arch
Server = http://mirrors.unal.edu.co/archlinux/\$repo/os/\$arch
Server = https://mirror.ufps.edu.co/archlinux/\$repo/os/\$arch
Server = http://mirror.ufps.edu.co/archlinux/\$repo/os/\$arch
## Global mirrors
Server = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch
MIRRORS_INSTALLED

# Actualizar en el sistema instalado
pacman -Syy
EOF

# Verificar particiones montadas
print_message "Verificando particiones montadas:"
mount | grep /mnt

# Limpiar y finalizar
print_message "Desmontando particiones..."
umount -R /mnt

print_message "¡Instalación completada!"
print_message "Particiones creadas:"
echo "sda1: 2G /boot (EFI)"
echo "sda2: 40G / (root)"
echo "sda3: 69.8G /home"
print_message "Kernel: Linux Zen"
print_message "Repositorios: Multilib y Extra activados"
print_message "Mirrors configurados para Colombia"
print_message ""
print_message "Reinicia el sistema y recuerda:"
print_message "1. Quitar el medio de instalación"
print_message "2. Iniciar sesión con tu usuario: $USERNAME"
print_message "3. Configurar NetworkManager si es necesario: sudo systemctl start NetworkManager"
