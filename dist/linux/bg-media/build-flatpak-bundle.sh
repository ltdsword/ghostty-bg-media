#!/usr/bin/env bash
# Build a single-file Flatpak release bundle for Ghostty Background Media.
# Usage: build-flatpak-bundle.sh [--out <dir>] [--state-dir <dir>]
# Needs flatpak-builder and the GNOME 50 SDK from Flathub; no root required.
set -euo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
out="$repo/zig-out/flatpak"
state="$repo/flatpak/.flatpak-builder"

usage() {
  printf 'Usage: %s [--out <dir>] [--state-dir <dir>]\n' "${0##*/}"
}

while (($#)); do
  case "$1" in
    --out)
      if (($# < 2)); then
        usage >&2
        exit 2
      fi
      out=$2
      shift 2
      ;;
    --state-dir)
      if (($# < 2)); then
        usage >&2
        exit 2
      fi
      state=$2
      shift 2
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

for program in flatpak flatpak-builder sha256sum; do
  if ! command -v "$program" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$program" >&2
    exit 1
  fi
done

version=$(git -C "$repo" describe --tags --always --dirty)
mkdir -p "$out"
flatpak-builder --user --install-deps-from=flathub --force-clean --state-dir="$state" \
  --repo="$out/repo" "$out/build" "$repo/flatpak/io.github.ltdsword.GhosttyBgMedia.yml"

bundle="$out/ghostty-bg-media-${version}-$(flatpak --default-arch).flatpak"
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "$out/repo" "$bundle" io.github.ltdsword.GhosttyBgMedia stable

(cd "$out" && sha256sum *.flatpak > SHA256SUMS)
printf 'Bundle: %s\n' "$bundle"
sha256sum "$bundle"
