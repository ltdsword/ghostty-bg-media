# Maintaining Ghostty Background Media

## Release process

1. Choose the next `bgm-v<MAJOR.MINOR.PATCH>[-beta[.N]]` tag. Keep the app version in `dist/linux/bg-media/build-deb.sh` and `flatpak/io.github.ltdsword.GhosttyBgMedia.yml` in sync with it. For this release, the app version is `1.3.2-bgm.0.1.0-beta` and the tag is `bgm-v0.1.0-beta`.
2. Build the `.deb` on Ubuntu 26.04 amd64 with `dist/linux/bg-media/build-deb.sh --version <app-version>`. Build the Flatpak bundle with `dist/linux/bg-media/build-flatpak-bundle.sh --name <tag>`.
3. Rename release files to the GitHub-safe names: `ghostty-bg-media-bgm-v0.1.0-beta-amd64.deb`, `ghostty-bg-media-bgm-v0.1.0-beta-x86_64.flatpak`, and `ghostty-bg-media-bgm-v0.1.0-beta-manifest.txt`.
4. From the directory containing the renamed files, create `SHA256SUMS` with `sha256sum ghostty-bg-media-bgm-v0.1.0-beta-amd64.deb ghostty-bg-media-bgm-v0.1.0-beta-x86_64.flatpak ghostty-bg-media-bgm-v0.1.0-beta-manifest.txt > SHA256SUMS`.
5. Check clean install, upgrade, removal, and rollback in an Ubuntu 26.04 container for the `.deb`; check install, version, media plugins, and uninstall in an Ubuntu 24.04 container for Flatpak. Check the packaged GUI on a supported host, including media and audio.
6. Create the matching git tag.
7. **Publish.** Install and authenticate GitHub CLI once with `sudo apt install gh` and `gh auth login`. The `--notes-file` path below is relative to the repository root; use an absolute path when running elsewhere.

   ```bash
   cd <release folder with the renamed assets>
   sha256sum -c SHA256SUMS
   gh release create bgm-v0.1.0-beta \
     -R ltdsword/ghostty-bg-media \
     --verify-tag --prerelease \
     --title "Ghostty Background Media bgm-v0.1.0-beta" \
     --notes-file docs/background-media/release-notes/bgm-v0.1.0-beta.md \
     ghostty-bg-media-bgm-v0.1.0-beta-amd64.deb \
     ghostty-bg-media-bgm-v0.1.0-beta-x86_64.flatpak \
     ghostty-bg-media-bgm-v0.1.0-beta-manifest.txt \
     SHA256SUMS
   ```

8. Verify the download flow from the release page. Download each asset, verify it with `sha256sum -c SHA256SUMS --ignore-missing`, and follow the install flow from a clean directory. Record that check in [STATUS.md](STATUS.md).

For a later release, bump the two app-version values and use the matching new tag and names throughout the release notes and checksums. Preserve the version rule: the first `-` in the app version becomes `+` in the Debian version; later `-` characters become `~` so beta packages sort before finals.

## Upstream sync

- Fetch `ghostty-org/ghostty` into an isolated branch and inspect the upstream changes before merging them into this fork.
- Merge; never force-push shared history. Rerun the build, tests, packaging checks, and platform-isolation gates after the merge.
- Protect `macos/**`, `BACKGROUND_VIDEO.md`, and the inherited `background-video*` behavior. Review media-library license changes before updating or redistributing dependencies.

## Contributing and security

Bug reports should include the Linux distribution, session type (Wayland, XWayland, or Xorg), install format, app version, relevant configuration, logs from `GHOSTTY_LOG` or stderr, and the media type/source category.

Report security issues through GitHub private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability**. Do not publish an email address for security reports.
