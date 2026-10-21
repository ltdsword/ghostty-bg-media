# macOS background-video baseline

Read-only inventory of the inherited macOS feature at baseline commit
24fa0219908a3b474eae4766440c3d3662106a3d. Source line references below refer to that
commit. Git refs, diff counts, and blob IDs are recorded from Git metadata.

## 1. Provenance

- Baseline branch mod/background-video resolves to 24fa0219908a3b474eae4766440c3d3662106a3d.
  contributor/mod/background-video resolves to the same object.
- The merge-base with upstream/main is 73e4ff10fb2b30d1ab6e6f7f52ef33f3a0593dcc.
- The six commits in 73e4ff10fb2b..24fa0219908a, from
  git log --format='%h %an %s', are all authored by locphamduc96:

  - 24fa02199 — macos: drop the markers of a parent Claude Code session from terminal shells
  - 1b4fff33a — macos: type the resume command for a coding assistant when restoring a window
  - c946d5298 — docs: add notes on the background video feature
  - 49d921c0c — macos: YouTube sign-in, frame rate cap and HLS fixes for background video
  - 3ab7bacad — macos: background video under the titlebar, pause and play in background
  - 999465c67 — macos: add background video behind the terminal

## 2. File inventory

The inherited diff has 12 paths, 1,626 insertions, and 2 deletions. Delta counts come from
git diff --stat/--numstat; baseline line counts and full blob IDs come from the 24fa0219908a
Git objects.

| Baseline path | Change | Delta (+/-) | Lines at baseline | Blob at baseline | Scope |
| --- | --- | ---: | ---: | --- | --- |
| BACKGROUND_VIDEO.md:1 | added | +115 / -0 | 115 | 579cde97a84ef4fdc6f03a55d8226ffd9d4dacb2 | macOS-only docs |
| macos/Sources/App/AppDelegate.swift:232 | modified | +2 / -0 | 1,445 | aac6fff1f7bd6918c4670674b048641c2bfd0a28 | macOS-only |
| macos/Sources/Features/Terminal/BackgroundVideo.swift:1 | added | +670 / -0 | 670 | 7a69532ca0c87902eae3d69f50afad452ba4b567 | macOS-only |
| macos/Sources/Features/Terminal/BackgroundVideoLogin.swift:1 | added | +163 / -0 | 163 | 0be56e780a8267aff4bde87aa9e236d3810d5291 | macOS-only |
| macos/Sources/Features/Terminal/BackgroundVideoPanel.swift:1 | added | +338 / -0 | 338 | b25240989867963615590e276f07ec39b5b67dc7 | macOS-only |
| macos/Sources/Features/Terminal/TerminalViewContainer.swift:13 | modified | +45 / -0 | 308 | 4e8ebcee13607b63ace0f2fdc61051e55ac1b0af | macOS-only |
| macos/Sources/Features/Terminal/Window Styles/TransparentTitlebarTerminalWindow.swift:16 | modified | +38 / -2 | 278 | 4524bcf28c6bdd1fc24273e58c3e400d344e2b5f | macOS-only |
| macos/Sources/Ghostty/Ghostty.Config.swift:80 | modified | +60 / -0 | 983 | 0f21e8baf294f00ac55be79cc35837ddaf3b26a2 | macOS-only |
| macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift:1878 | modified | +106 / -0 | 2,626 | 5717b1538836f1e6d376813b4c149a8a185fa878 | macOS-only |
| src/apprt/embedded.zig:1233 | modified | +18 / -0 | 2,594 | 344def48d779f0aee50e214cbb60eb87bedd7766 | shared |
| src/config/Config.zig:708 | modified | +62 / -0 | 11,447 | 491339b6acc26fbc0c7c90b89b2b229ff04de4d5 | shared |
| src/renderer/generic.zig:596 | modified | +9 / -0 | 3,691 | e1be37c6dfe7293c1d7540ac023f5c3c14b3e628 | shared |

## 3. Architecture

### Player and source resolution

BackgroundVideoPlayer.shared owns one AVPlayer for all windows. Each window contributes an
AVPlayerLayer, so the source is decoded once. End-of-item notification seeks to zero to loop.
(macos/Sources/Features/Terminal/BackgroundVideo.swift:7-14, 21-27, 208-210)

Local paths and file URLs go directly to AVFoundation. HTTP(S) URLs ending in mp4, m4v, mov, or
m3u8 also go directly to AVFoundation; other HTTP(S) page URLs are passed to yt-dlp.
(macos/Sources/Features/Terminal/BackgroundVideo.swift:296-297, 323-343)

The ordinary yt-dlp argv is:

    --dump-json --no-playlist --no-warnings -f FORMAT PAGE_URL

FORMAT is the slash-separated fallback list
bestvideo[vcodec^=avc1][height<=1080][fps<=?MAX_FPS][protocol^=m3u8] /
best[vcodec^=avc1][height<=1080][fps<=?MAX_FPS][protocol^=m3u8] /
bestvideo[vcodec^=avc1][height<=1080][fps<=?MAX_FPS] /
best[vcodec^=avc1][height<=1080][fps<=?MAX_FPS] / best.
The selector prefers HLS and H.264, caps selected formats at 1080p and the configured frame
rate, then falls back to the best available format. (macos/Sources/Features/Terminal/BackgroundVideo.swift:299-315, 368-381)

When the app's sign-in cookies are present and yt-dlp fails with “Sign in to confirm”, the retry
adds --no-cookies-from-browser, --cookies COOKIE_FILE, and
--extractor-args youtube:player_client=default,web_safari before the ordinary argv.
(macos/Sources/Features/Terminal/BackgroundVideo.swift:345-356, 368-381)

Missing local files, missing yt-dlp, and yt-dlp failures become user-facing errors. yt-dlp
stderr's last line is used on a nonzero exit. Failed AVPlayer items and items still unknown after
30 seconds report an error and retry; the retry delay starts at 5 seconds, doubles, and caps at
300 seconds. File-not-found and missing-yt-dlp resolution errors are not marked retryable.
There is no explicit timeout around Process execution in this code. HLS manifest fetches use a
15-second URLRequest timeout. (macos/Sources/Features/Terminal/BackgroundVideo.swift:57-62,
217-240, 247-259, 274-293, 388-410, 434-445)

### HLS handling

For yt-dlp results identified as m3u8, the resolver fetches the manifest. It either narrows a
multi-audio master playlist to the best matching H.264 variant and associated audio group, or
selects a matching variant URL. PlaylistLoader serves rewritten playlist data to AVPlayer on a
custom URL scheme; the variant and audio playlists remain remote.
(macos/Sources/Features/Terminal/BackgroundVideo.swift:419-431, 451-472, 482-526)

### YouTube sign-in and cookies

Sign-in uses an app-owned WKWebView and separate web data store. Relevant YouTube and Google
cookies are written in Netscape format under the app's Application Support directory; sign-out
attempts to remove the file. This is security-sensitive session material: the file is created
and set to owner-only mode 0600. No cookie values belong in this inventory.
(macos/Sources/Features/Terminal/BackgroundVideoLogin.swift:5-10, 19-28, 70-78, 105-138)

### View and compositing

TerminalViewContainer adds a full-size BackgroundVideoView below its terminal content. Each view
uses the shared AVPlayer through an aspect-fill AVPlayerLayer, a CALayer tint using the terminal
background color and configured tint opacity, and a CIGaussianBlur filter on the video layer.
The view does not take mouse events. (macos/Sources/Features/Terminal/TerminalViewContainer.swift:99-134;
macos/Sources/Features/Terminal/BackgroundVideo.swift:557-590, 625-643)

When background-video is set, generic.zig sets terminal background alpha to zero only inside a
macOS compile-time branch. The macOS view then applies the background-color tint; the
background-video-opacity value is tint strength, not video-texture opacity.
(src/renderer/generic.zig:1687-1692; macos/Sources/Features/Terminal/BackgroundVideo.swift:571-579)

With transparent titlebar style, the window extends content beneath the titlebar and clears its
titlebar background to show the video. (macos/Sources/Features/Terminal/Window Styles/TransparentTitlebarTerminalWindow.swift:16-30, 100-113, 127-135, 153-168)

### Visibility, audio, frame rate, retries, and threads

Playback is wanted while at least one registered video view has a window and either one such
window is visible or play-in-background is enabled. A manual pause overrides both. With no
window, playback pauses even when play-in-background is enabled.
(macos/Sources/Features/Terminal/BackgroundVideo.swift:140-151, 645-668)

Volume is applied to AVPlayer; values at or below zero mute it. max-fps is a selection constraint
for yt-dlp page resolution and HLS variant filtering. Changing it reloads an HTTP source; local
files and direct links play at their own rate. The player also sets a 1920x1080 maximum adaptive
resolution. (macos/Sources/Features/Terminal/BackgroundVideo.swift:64-66, 87-90, 104-119,
307-315, 482-496)

Resolution runs on a global utility queue and returns to the main queue before installing the
AVPlayer item. The HLS resource-loader delegate is assigned the main queue; yt-dlp is waited on
synchronously by the resolver, and the blocking manifest fetch also runs during off-main
resolution. (macos/Sources/Features/Terminal/BackgroundVideo.swift:154-175, 179-190, 359-405,
434-445)

## 4. Settings and persistence

| Key | Zig type and default | Config documentation summary | Swift accessor |
| --- | --- | --- | --- |
| background-video | ?[:0]const u8 = null | Local path, direct video/HLS URL, or page URL resolved by yt-dlp; macOS only. | backgroundVideo: String? |
| background-video-play-in-background | bool = false | Continue when windows are covered/minimized; stop with no open video window. | backgroundVideoPlayInBackground: Bool |
| background-video-max-fps | u32 = 60 | Highest offered frame rate for adaptive sources; panel has 30 and 60; no effect on local/direct sources. | backgroundVideoMaxFps: Int |
| background-video-opacity | f64 = 0.3 | Strength of background-color tint over video; 0 shows video, 1 hides it. | backgroundVideoOpacity: Double |
| background-video-blur | f64 = 2 | Video blur radius in points, separate from desktop background blur. | backgroundVideoBlur: Double |
| background-video-volume | f64 = 0 | Player volume from muted 0 to 1. | backgroundVideoVolume: Double |

Zig declarations and documentation are at src/config/Config.zig:708-754. Swift accessors use
ghostty_config_get at macos/Sources/Ghostty/Ghostty.Config.swift:502-550.

The panel path is $XDG_CONFIG_HOME/ghostty/background-video.conf, falling back to
~/.config/ghostty/background-video.conf. It writes all six keys, writes an empty source when
turned off, and saves atomically. Config loading processes the selected/default config, CLI
arguments when applicable, recursive files, then this panel file, and then finalizes; therefore
the panel file has last precedence for these settings. Saving reloads app config.
(macos/Sources/Features/Terminal/BackgroundVideoPanel.swift:6-50, 223-239;
macos/Sources/Ghostty/Ghostty.Config.swift:67-90)

AppDelegate installs the panel items into its menu. Background Video… uses Cmd+Shift+B;
Pause/Resume uses Cmd+Option+B. (macos/Sources/App/AppDelegate.swift:229-233;
macos/Sources/Features/Terminal/BackgroundVideoPanel.swift:54-83)

## 5. Shared-code touchpoints

- src/renderer/generic.zig adds the derived background_video flag and, only on macOS at
  compile time, zeros background alpha when that flag is set
  (src/renderer/generic.zig:596, src/renderer/generic.zig:655-659,
  src/renderer/generic.zig:1687-1692).
- src/apprt/embedded.zig adds 18 lines removing inherited Claude Code session-marker
  environment variables from child terminal environments, so a nested Claude Code process
  does not mistake itself for a child session and skip saving its transcript. This is unrelated
  to video (src/apprt/embedded.zig:1230-1249).
- macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift adds coding-assistant detection
  and restoration: it records the running assistant and types a resume command when restoring
  a saved terminal, without pressing Enter. This is unrelated to video
  (macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift:1871-1957,
  macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift:2000-2018).

Linux work must preserve this invariant: merely having background-video configured must not
zero terminal background alpha on Linux. The alpha-zeroing branch is macOS compile-time-only;
the existing Linux background-opacity and background-image composition remains in effect.
(src/renderer/generic.zig:656-658, src/renderer/generic.zig:1670-1692;
src/config/Config.zig:611-626)

## 6. Baseline behavior to regress against (MAC-01)

Every item below is UNVERIFIED (no macOS host); expected results are inferred from source.

1. **UNVERIFIED (no macOS host) — Local file:** choose a local video and expect AVPlayer to load
   it behind the terminal and seek to the start at end of item.
   (macos/Sources/Features/Terminal/BackgroundVideo.swift:199-210,
   macos/Sources/Features/Terminal/BackgroundVideo.swift:323-343)
2. **UNVERIFIED (no macOS host) — Direct HLS URL:** enter an m3u8 URL and expect AVPlayer to load
   it directly with the adaptive-resolution ceiling.
   (macos/Sources/Features/Terminal/BackgroundVideo.swift:179-197,
   macos/Sources/Features/Terminal/BackgroundVideo.swift:296-297)
3. **UNVERIFIED (no macOS host) — YouTube watch URL:** expect a page URL to resolve through
   yt-dlp and select an eligible H.264 format, preferring HLS.
   (macos/Sources/Features/Terminal/BackgroundVideo.swift:299-315,
   macos/Sources/Features/Terminal/BackgroundVideo.swift:323-356,
   macos/Sources/Features/Terminal/BackgroundVideo.swift:368-381)
4. **UNVERIFIED (no macOS host) — YouTube live:** expect the live page URL to use the same
   yt-dlp path and HLS selection; the config documentation lists live URLs as a source.
   (src/config/Config.zig:711-714;
   macos/Sources/Features/Terminal/BackgroundVideo.swift:323-356,
   macos/Sources/Features/Terminal/BackgroundVideo.swift:419-431)
5. **UNVERIFIED (no macOS host) — Panel and persistence:** open with Cmd+Shift+B, apply a source
   or tune a setting, restart/reload, and expect the panel file to load after other config files.
   (macos/Sources/Features/Terminal/BackgroundVideoPanel.swift:21-50,
   macos/Sources/Features/Terminal/BackgroundVideoPanel.swift:54-70,
   macos/Sources/Features/Terminal/BackgroundVideoPanel.swift:198-239;
   macos/Sources/Ghostty/Ghostty.Config.swift:80-82)
6. **UNVERIFIED (no macOS host) — Opacity, blur, volume:** change controls and expect tint, blur,
   and volume to preview live; opacity is background-color tint strength.
   (macos/Sources/Features/Terminal/BackgroundVideoPanel.swift:210-220,
   macos/Sources/Features/Terminal/BackgroundVideoPanel.swift:277-295;
   macos/Sources/Features/Terminal/TerminalViewContainer.swift:116-120;
   macos/Sources/Features/Terminal/BackgroundVideo.swift:87-90,
   macos/Sources/Features/Terminal/BackgroundVideo.swift:571-639)
7. **UNVERIFIED (no macOS host) — Hide window / play in background:** expect automatic pause
   when no showing window is visible by default; enabling the setting keeps playback while a
   video window exists. It still pauses when no video window remains.
   (macos/Sources/Features/Terminal/BackgroundVideo.swift:140-151;
   src/config/Config.zig:725-731)
8. **UNVERIFIED (no macOS host) — Multi-window:** expect each window to show the same stream
   through its own layer while sharing one AVPlayer decode and audio track.
   (macos/Sources/Features/Terminal/BackgroundVideo.swift:7-14,
   macos/Sources/Features/Terminal/BackgroundVideo.swift:48-51;
   macos/Sources/Features/Terminal/TerminalViewContainer.swift:102-134)

## 7. macOS build recipe

Proposal only; UNVERIFIED. The existing build-macos job selects Xcode 26.6, builds GhosttyKit
with zig build --system <deps> -Demit-macos-app=false, then runs xcodebuild -target Ghostty
from macos/. HACKING.md requires Xcode, the macOS SDK, and Metal Toolchain and names Xcode 26
and the macOS 26 SDK. (.github/workflows/test.yml:1300-1350; HACKING.md:50-68)

For a GitHub-hosted macOS job without Namespace, Nix, or Cachix, provision a runner with
Xcode_26.6 and the repository-required Zig version (minimum 0.16.0), then provide a
system-dependency prefix in
the layout expected by zig's --system option. This replaces the workflow's Nix dependency
prefix; its provisioning is not established by the inherited job and remains UNVERIFIED.
Run the GhosttyKit Zig command and the native Xcode target as separate steps, with xcodebuild
outside any Nix environment:

    sudo xcode-select -s /Applications/Xcode_26.6.app
    xcodebuild -version
    zig build --system "$GHOSTTY_SYSTEM_DEPS" -Demit-macos-app=false
    cd macos && xcodebuild -target Ghostty

The runner image, system-dependency provisioning, and successful build are UNVERIFIED.
(.github/workflows/test.yml:1327-1350; HACKING.md:52-68; build.zig.zon:6)

## 8. Capability gap vs Linux targets (M18 input)

This table records inherited source paths only. All runtime results are UNVERIFIED.

| Source/type | Inherited macOS support indicated by source | Evidence | Runtime |
| --- | --- | --- | --- |
| PNG | Yes through Ghostty background-image. | src/config/Config.zig:611-626; src/renderer/generic.zig:2113-2116 | UNVERIFIED |
| JPEG | Yes through Ghostty background-image. | src/config/Config.zig:611-626; src/renderer/generic.zig:2113-2116 | UNVERIFIED |
| WebP | No background-image decoder path; only PNG/JPEG decode cases are handled. | src/config/Config.zig:611-614; src/renderer/generic.zig:2113-2129 | UNVERIFIED |
| GIF | No background-image decoder path, and gif is absent from the direct-video extension allowlist. AVPlayer GIF behavior is not tested in source. | src/renderer/generic.zig:2113-2129; macos/Sources/Features/Terminal/BackgroundVideo.swift:296-297 | UNVERIFIED |
| MP4 | Accepted as a direct HTTP extension; local paths are also passed to AVFoundation. | macos/Sources/Features/Terminal/BackgroundVideo.swift:179-197, 296-297, 323-343 | UNVERIFIED |
| HLS | m3u8 is a direct extension; yt-dlp HLS results may be narrowed and rewritten. | macos/Sources/Features/Terminal/BackgroundVideo.swift:296-297, 419-431, 451-526 | UNVERIFIED |
| YouTube recording | Page URLs use yt-dlp, with H.264 and HLS-preferred selection. | src/config/Config.zig:711-714; macos/Sources/Features/Terminal/BackgroundVideo.swift:299-315, 323-356 | UNVERIFIED |
| YouTube live | Config documents live page URLs; resolver uses the page-URL path and HLS selection, with no separate live-specific branch. | src/config/Config.zig:711-714; macos/Sources/Features/Terminal/BackgroundVideo.swift:323-356, 419-431 | UNVERIFIED |

## 9. Protected-path list for the isolation gate

Preserve these exact inherited paths as the baseline. The three shared Zig paths may receive
additive Linux work only where existing macOS behavior and unrelated inherited changes remain
intact. In particular, retain macOS-only alpha zeroing and existing background-image semantics.
(src/renderer/generic.zig:1687-1692; src/config/Config.zig:611-754)

- BACKGROUND_VIDEO.md
- macos/Sources/App/AppDelegate.swift
- macos/Sources/Features/Terminal/BackgroundVideo.swift
- macos/Sources/Features/Terminal/BackgroundVideoLogin.swift
- macos/Sources/Features/Terminal/BackgroundVideoPanel.swift
- macos/Sources/Features/Terminal/TerminalViewContainer.swift
- macos/Sources/Features/Terminal/Window Styles/TransparentTitlebarTerminalWindow.swift
- macos/Sources/Ghostty/Ghostty.Config.swift
- macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift
- src/apprt/embedded.zig
- src/config/Config.zig
- src/renderer/generic.zig
