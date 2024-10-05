#!/bin/bash

set -euo pipefail

declare -r WRAPPER="fakechroot -- fakeroot"

declare -r GROUP="$1"
declare -r BUILDDIR="$2"
declare -r OUTPUTDIR="$3"

mkdir -vp "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks"
find /usr/share/libalpm/hooks -exec ln -sf /dev/null "$BUILDDIR/alpm-hooks"{} \;

mkdir -vp "$BUILDDIR/var/lib/pacman/" "$OUTPUTDIR"
[[ "$GROUP" == "multilib-devel" ]] && pacman_conf=pacman-multilib.conf || pacman_conf=pacman-extra.conf
install -Dm644 "/usr/share/devtools/$pacman_conf" "$BUILDDIR/etc/pacman.conf"
cat pacman-conf.d-noextract.conf >> "$BUILDDIR/etc/pacman.conf"

sed 's/Include = /&rootfs/g' < "$BUILDDIR/etc/pacman.conf" > pacman.conf

cp --recursive --preserve=timestamps rootfs/* "$BUILDDIR/"
ln -fs /usr/lib/os-release "$BUILDDIR/etc/os-release"

$WRAPPER -- \
    pacman -Sy -r "$BUILDDIR" \
        --noconfirm --dbpath "$BUILDDIR/var/lib/pacman" \
        --config pacman.conf \
        --noscriptlet \
        --hookdir "$BUILDDIR/alpm-hooks/usr/share/libalpm/hooks/" base "$GROUP" archlinuxarm-keyring

$WRAPPER -- chroot "$BUILDDIR" update-ca-trust
$WRAPPER -- chroot "$BUILDDIR" pacman-key --init
$WRAPPER -- chroot "$BUILDDIR" pacman-key --populate

# add system users
$WRAPPER -- chroot "$BUILDDIR" /usr/bin/systemd-sysusers --root "/"

# remove passwordless login for root (see CVE-2019-5021 for reference)
sed -i -e 's/^root::/root:!:/' "$BUILDDIR/etc/shadow"

# fakeroot to map the gid/uid of the builder process to root
# fixes #22
fakeroot -- \
    tar \
        --numeric-owner \
        --xattrs \
        --acls \
        --exclude-from=exclude \
        -C "$BUILDDIR" \
        -c . \
        -f "$OUTPUTDIR/$GROUP.tar"

cd "$OUTPUTDIR"
zstd --long -T0 -8 "$GROUP.tar"
sha256sum "$GROUP.tar.zst" > "$GROUP.tar.zst.SHA256"
