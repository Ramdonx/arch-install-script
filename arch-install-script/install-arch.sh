#!/bin/bash

# Script de instalación de Arch Linux
# IMPORTANTE: Ejecutar desde el live environment de Arch

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar live environment
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

# Variables de configuración (MODIFICA ESTAS)
DISK="/dev/sda"
HOSTNAME="arch-machine"
USERNAME="usuario"
USER_PASSWORD="password123"
ROOT_PASSWORD="root123"
TIMEZONE="America/Bogota"
KEYMAP="la-latin1"

# Tamaños de partición (sda1 y sda2 fijos, sda3 usa el resto)
BOOT_SIZE="2GiB"
ROOT_SIZE="40GiB"

# Confirmación
print_warning "Este script formateará el disco: $DISK"
print_warning "Se crearán las siguientes particiones:"
print_warning "sda1: $BOOT_SIZE /boot"
print_warning "sda2: $ROOT_SIZE /"
print_warning "sda3: (espacio restante) /home"
print_warning "¿Continuar? (s/N)"
read -r confirmation
if [[ ! $confirmation =~ ^[Ss]$ ]]; then
    print_message "Instalación cancelada."
    exit 0
fi

# CONFIGURAR MIRRORS CON REFLECTOR (ACTUALIZADO)
print_message "Instalando y configurando reflector..."
pacman -Sy --noconfirm reflector

# Usar reflector para obtener los mirrors más rápidos
print_message "Buscando los mirrors más rápidos con reflector..."
reflector \
    --protocol https,http \
    --latest 20 \
    --sort rate \
    --save /etc/pacman.d/mirrorlist

print_message "Mirrors más rápidos configurados:"
cat /etc/pacman.d/mirrorlist | head -5

# Sincronizar hora
print_message "Sincronizando hora..."
timedatectl set-ntp true

# Particionado con espacio restante automático
print_message "Creando particiones..."
wipefs -a "$DISK"
parted -s "$DISK" mklabel gpt

# sda1: Boot (tamaño fijo)
parted -s "$DISK" mkpart "boot" fat32 1MiB $BOOT_SIZE
parted -s "$DISK" set 1 esp on

# sda2: Root (tamaño fijo)
parted -s "$DISK" mkpart "root" ext4 $BOOT_SIZE $ROOT_SIZE

# sda3: Home (usa TODO el espacio restante)
parted -s "$DISK" mkpart "home" ext4 $ROOT_SIZE 100%

# Mostrar las particiones creadas
print_message "Particiones creadas:"
parted -s "$DISK" print

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

# Mostrar información del espacio
print_message "Información del espacio en particiones:"
lsblk -f "$DISK"

# Configurar pacman.conf ACTUALIZADO (sin community)
print_message "Configurando pacman.conf actualizado..."
cat > /etc/pacman.conf << 'PACMANCONF'
[options]
HoldPkg = pacman glibc
Architecture = auto

# Misc options
Color
CheckSpace
VerbosePkgLists
ParallelDownloads = 5

# Repositories ACTUALIZADOS - community fue fusionado con extra
[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
PACMANCONF

# ACTUALIZAR BASE DE DATOS
print_message "Actualizando base de datos de paquetes..."
pacman -Syy

# Instalar sistema base con kernel Zen
print_message "Instalando sistema base con kernel Zen..."
pacstrap /mnt base base-devel linux-zen linux-zen-headers linux-firmware

# Generar fstab
print_message "Generando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Configuración del sistema
print_message "Configurando sistema..."

arch-chroot /mnt /bin/bash << CHROOT_EOF
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
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS_EOF

# Configurar contraseñas
echo "root:$ROOT_PASSWORD" | chpasswd

# Crear usuario
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Configurar sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Instalar reflector en el sistema instalado
pacman -S --noconfirm reflector

# Configurar pacman.conf en el sistema instalado (ACTUALIZADO)
cat > /etc/pacman.conf << PACMAN_INSTALLED
[options]
HoldPkg = pacman glibc
Architecture = auto

# Misc options
Color
CheckSpace
VerbosePkgLists
ParallelDownloads = 5

# Repositories ACTUALIZADOS - sin community
[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
PACMAN_INSTALLED

# ACTUALIZAR MIRRORS EN EL SISTEMA INSTALADO CON REFLECTOR
print_message "Actualizando mirrors en el sistema instalado..."
reflector \
    --country Colombia,Argentina,Brazil \
    --protocol https \
    --latest 12 \
    --sort rate \
    --save /etc/pacman.d/mirrorlist

echo "Mirrors actualizados en el sistema instalado:"
cat /etc/pacman.d/mirrorlist | head -5

# Actualizar sistema
pacman -Syy

# Instalar paquetes necesarios
pacman -S --noconfirm grub efibootmgr dosfstools mtools networkmanager sudo vim git

# Configurar GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Habilitar NetworkManager
systemctl enable NetworkManager

# Crear servicio para actualizar mirrors automáticamente
cat > /etc/systemd/system/update-mirrors.service << SERVICE
[Unit]
Description=Update pacman mirrors
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/reflector --protocol https,http --latest 20 --sort rate --save /etc/pacman.d/mirrorlist

[Install]
WantedBy=multi-user.target
SERVICE

# Crear timer para actualizar mirrors semanalmente
cat > /etc/systemd/system/update-mirrors.timer << TIMER
[Unit]
Description=Update mirrors weekly
Requires=update-mirrors.service

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
TIMER

systemctl enable update-mirrors.timer

# Mostrar información final del espacio
echo "=== ESPACIO FINAL DE PARTICIONES ==="
df -h /boot / /home

# Mostrar información de mirrors
echo "=== INFORMACIÓN DE MIRRORS ==="
echo "Mirrors configurados: $(grep -c '^Server' /etc/pacman.d/mirrorlist)"
echo "Servicio de actualización automática de mirrors: ACTIVADO"
CHROOT_EOF

# Verificar particiones
print_message "Verificando particiones montadas:"
mount | grep /mnt

# Limpiar
print_message "Desmontando particiones..."
umount -R /mnt

print_message "¡Instalación completada!"
print_message "Estructura final de particiones:"
print_message "sda1: $BOOT_SIZE /boot"
print_message "sda2: $ROOT_SIZE /"
print_message "sda3: (todo el espacio restante) /home"
print_message "Kernel: Linux Zen"
print_message "Mirrors: Configurados automáticamente con reflector"
print_message "Actualización automática: Activada semanalmente"
print_message "Repositorios: core, extra, multilib (sin community)"
print_message "Reinicia y quita el medio de instalación"