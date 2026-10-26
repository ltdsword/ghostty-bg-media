#!/usr/bin/env bash
# Build an installable Ghostty Background Media .deb package.
# Usage: dist/linux/bg-media/build-deb.sh [--version <app-version>] [--revision <n>] [--out <dir>]
# Requires no root privileges. Run on Ubuntu 26.04 with the build dependencies from
# docs/background-media/BUILDING.md, dpkg-dev, and Zig.

set -euo pipefail

version=1.3.2-bgm.0.2.0-beta
revision=1
out=

while (($#)); do
    case "$1" in
        --version)
            if (($# < 2)); then
                printf 'error: --version requires a value\n' >&2
                exit 2
            fi
            version=$2
            shift 2
            ;;
        --revision)
            if (($# < 2)); then
                printf 'error: --revision requires a value\n' >&2
                exit 2
            fi
            revision=$2
            shift 2
            ;;
        --out)
            if (($# < 2)); then
                printf 'error: --out requires a value\n' >&2
                exit 2
            fi
            out=$2
            shift 2
            ;;
        *)
            printf 'error: unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
for command in zig dpkg-deb dpkg-shlibdeps sha256sum; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'error: required command not found: %s\n' "$command" >&2
        exit 1
    fi
done
arch=$(dpkg --print-architecture)

if [[ -z "$out" ]]; then
    out="$repo/zig-out/deb"
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
root="$stage/root"
opt="$root/opt/ghostty-bg-media"

(cd "$repo" && DESTDIR="$root" zig build --prefix /opt/ghostty-bg-media -Doptimize=ReleaseFast -Dcpu=baseline -Dpie=true -Dversion-string="$version")

rm -rf \
    "$opt/include" \
    "$opt/lib" \
    "$opt/share/pkgconfig" \
    "$opt/share/applications" \
    "$opt/share/dbus-1" \
    "$opt/share/systemd" \
    "$opt/share/metainfo" \
    "$opt/share/kio" \
    "$opt/share/nautilus-python"

install -D -m 0755 "$repo/dist/linux/bg-media/ghostty-bg-media" "$root/usr/bin/ghostty-bg-media"
install -D -m 0644 \
    "$repo/dist/linux/bg-media/io.github.ltdsword.GhosttyBgMedia.desktop" \
    "$root/usr/share/applications/io.github.ltdsword.GhosttyBgMedia.desktop"

shopt -s nullglob
for icon in "$opt"/share/icons/hicolor/*/apps/com.mitchellh.ghostty.png; do
    size=${icon#"$opt/share/icons/hicolor/"}
    size=${size%%/*}
    install -D -m 0644 "$icon" \
        "$root/usr/share/icons/hicolor/$size/apps/io.github.ltdsword.GhosttyBgMedia.png"
done
shopt -u nullglob
rm -rf "$opt/share/icons"

mkdir -p "$root/usr/share/doc/ghostty-bg-media"
copyright="$root/usr/share/doc/ghostty-bg-media/copyright"
{
    printf '%s\n\n' 'Unofficial build of Ghostty with background media. Source: https://github.com/ltdsword/ghostty-bg-media. Ghostty: https://github.com/ghostty-org/ghostty'
    cat "$repo/LICENSE"
} > "$copyright"
chmod 0644 "$copyright"

mkdir -p "$stage/debian"
printf 'Source: ghostty-bg-media\n\nPackage: ghostty-bg-media\nArchitecture: any\n' > "$stage/debian/control"
shlibs_output=$(cd "$stage" && dpkg-shlibdeps -O root/opt/ghostty-bg-media/bin/ghostty)
depends=${shlibs_output#shlibs:Depends=}

head=${version%%-*}
rest=${version#*-}
[ "$head" = "$version" ] && debversion=$version || debversion="$head+${rest//-/\~}"
debversion="$debversion-$revision"
mkdir -p "$root/DEBIAN"
installed_size=$(du -sk --exclude=DEBIAN "$root" | cut -f1)
cat > "$root/DEBIAN/control" <<EOF
Package: ghostty-bg-media
Version: $debversion
Architecture: $arch
Maintainer: ltdsword <ltdsword@users.noreply.github.com>
Installed-Size: $installed_size
Depends: $depends
Recommends: gstreamer1.0-plugins-good, gstreamer1.0-plugins-bad, gstreamer1.0-libav, yt-dlp
Section: x11
Priority: optional
Homepage: https://github.com/ltdsword/ghostty-bg-media
Description: Ghostty terminal with image, GIF, video and livestream backgrounds
 Unofficial build of the Ghostty terminal emulator with configurable terminal
 backgrounds: static images, animated GIFs, local video, web video and
 livestreams. Installs side by side with the official Ghostty as the
 ghostty-bg-media command (files in /opt/ghostty-bg-media); it does not
 replace /usr/bin/ghostty. Shares the user's Ghostty configuration.
EOF

find "$root" -type d -exec chmod 0755 {} +
find "$root" -type f ! -perm /111 -exec chmod 0644 {} +
find "$root" -type f -perm /111 -exec chmod 0755 {} +

mkdir -p "$out"
deb="ghostty-bg-media_${debversion}_${arch}.deb"
deb_path="$out/$deb"
dpkg-deb --root-owner-group -Zxz --build "$root" "$deb_path"

git_commit=$(git -C "$repo" rev-parse HEAD)
if [[ -n $(git -C "$repo" status --porcelain) ]]; then
    git_dirty=yes
else
    git_dirty=no
fi
built_on=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | sed -e 's/^"//' -e 's/"$//')
zig_version=$(zig version)
built_at=$(date -u +%FT%TZ)
deb_sha=$(cd "$out" && sha256sum "$deb")
deb_sha=${deb_sha%% *}
manifest="$out/ghostty-bg-media_${debversion}_${arch}.manifest.txt"
cat > "$manifest" <<EOF
package=ghostty-bg-media
version=$version
deb_version=$debversion
git_commit=$git_commit
git_dirty=$git_dirty
built_on=$built_on
zig=$zig_version
built_at=$built_at
sha256=$deb_sha
EOF

(cd "$out" && sha256sum *.deb > SHA256SUMS)
printf '%s\nsha256: %s\n' "$deb_path" "$deb_sha"
