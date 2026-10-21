# Background media project status

Milestone states follow the master plan (Agent-Kit workspace `docs/MASTER_PLAN.md`) §7A. PARTIAL means the
evidence below exists but the milestone exit gate is not complete. No milestone commit is recorded
yet.

| Milestone | Owner | State | Commit | Evidence | Blockers | Next task |
| --- | --- | --- | --- | --- | --- | --- |
| M00 — Baselines | T2 audit | PARTIAL | — | [BASELINE](BASELINE.md), [macOS baseline](MACOS_BASELINE.md), gate log (Agent-Kit workspace `notes/m00/gate-full-baseline.log`) | Linux app launch and macOS build/runtime unverified | Complete approved Linux and macOS baseline runs |
| M01 — Build environment | T3–T4 environment | PARTIAL | — | [BUILDING](BUILDING.md), [options](BUILD_ENV_OPTIONS.md), [M01 evidence](evidence/m01/) | Host GTK blocked by libadwaita 1.5 < 1.7 and absent Blueprint compiler; Flatpak build stopped at bwrap; launch unverified | Evidence a GTK build and launch in the approved Flatpak lane |
| M02 — Compositor spike | TBD | NOT_STARTED | — | — | — | Prove terminal-over-media composition |
| M03 — Domain/config | TBD | NOT_STARTED | — | — | — | Decide config and source contracts |
| M04 — Static images | TBD | NOT_STARTED | — | — | — | Implement PNG/JPEG/WebP media behavior |
| M05 — Local MP4 | TBD | NOT_STARTED | — | — | — | Select and integrate a backend after M02 |
| M06 — GIF | TBD | NOT_STARTED | — | — | — | Implement animation timing and disposal |
| M07 — HTTP/HLS | TBD | NOT_STARTED | — | — | — | Add direct streaming and reconnect behavior |
| M08 — YouTube recorded | TBD | NOT_STARTED | — | — | — | Add Linux-only recorded-video resolution |
| M09 — YouTube live | TBD | NOT_STARTED | — | — | — | Add live state and recovery behavior |
| M10 — GTK controls | TBD | NOT_STARTED | — | — | — | Add GTK controls and keyboard UX |
| M11 — Lifecycle | TBD | NOT_STARTED | — | — | — | Verify tabs, splits, windows, and sessions |
| M12 — Effects/performance | TBD | NOT_STARTED | — | — | — | Measure quality and resource use |
| M13 — Security/regression | TBD | NOT_STARTED | — | — | — | Run robustness and compatibility suite |
| M14 — Docs/release candidate | TBD | NOT_STARTED | — | — | — | Prepare package and handoff documentation |
| M15 — CI lanes | TBD | NOT_STARTED | — | — | — | Establish independent Linux/macOS CI |
| M16 — Public packaging | TBD | NOT_STARTED | — | — | App ID/coexistence decision; install gate | Verify clean Flatpak install, upgrade, and removal |
| M17 — Public beta | TBD | NOT_STARTED | — | — | — | Publish only after release gates pass |
| M18 — Optional macOS parity | TBD | NOT_STARTED | — | Approval required | — | Seek approval before considering additive parity |

## M00 — Fork inheritance and baselines

- **Milestone:** M00 — Fork inheritance, repository audit, dual-platform baselines
- **Status:** PARTIAL
- **Branch / commit:** `feat/linux-background-media` is recorded at baseline `24fa0219908a`; the
  audit task branch was `agent/m00-m01-t2` at that SHA.
- **Changed files:** `docs/background-media/BASELINE.md`,
  `docs/background-media/MACOS_BASELINE.md`.
- **Decisions:** D-001 and D-002 are ACCEPTED; D-005 records the M02 compositor proposal.
- **Build commands + results:** Host `zig build -Dapp-runtime=none -Demit-docs=false test`
  passed in the M00/M01 gate. GTK build was skipped because host libadwaita 1.5 is below the
  source floor 1.7.
- **Automated tests + results:** The same host core test passed; macOS build was not run.
- **Manual visual/functional tests + environment:** Linux app launch and macOS playback were not
  run; both remain UNVERIFIED.
- **Performance / resource measurements:** No media performance measurements.
- **Platform-isolation check:** macOS file inventory and Linux/macOS ownership boundaries are
  documented; the gate's macOS-untouched and no-Apple-framework-in-GTK checks passed.
- **Linux evidence:** [baseline](BASELINE.md),
  gate log (Agent-Kit workspace `notes/m00/gate-full-baseline.log`).
- **macOS CI evidence:** UNVERIFIED; no macOS runner result is recorded.
- **Remaining risks:** No target-host GTK build/launch and no macOS build or runtime validation.
- **Next task:** Complete the approved Linux build/launch lane and establish macOS CI evidence.

## M01 — Developer environment and checks

- **Milestone:** M01 — Developer environment, reproducible build and checks
- **Status:** PARTIAL
- **Branch / commit:** `feat/linux-background-media` at baseline `24fa0219908a`; no M01 commit is
  recorded.
- **Changed files:** `docs/background-media/BUILDING.md`,
  `docs/background-media/BUILD_ENV_OPTIONS.md`, and `docs/background-media/evidence/m01/`.
- **Decisions:** D-003, D-004, and D-006 are ACCEPTED. Flatpak is the Linux development-run and
  distribution format; the Ubuntu 26.04 container remains a dev-only compile/test lane.
- **Build commands + results:** The GTK app built in the Ubuntu 26.04 container after a transient
  fetch failure; the Flatpak builder stopped at bwrap namespace creation. The GTK app was not
  built by the Flatpak lane.
- **Automated tests + results:** Host `zig build -Dapp-runtime=none -Demit-docs=false test`
  passed. Both container test targets stopped during test-binary compilation with SIGKILL; test
  execution did not start.
- **Manual visual/functional tests + environment:** The container launch failed before Ghostty
  started because Docker Desktop could not resolve `/dev/dri`; visual result UNVERIFIED. Flatpak
  app launch is also UNVERIFIED.
- **Performance / resource measurements:** No media performance measurements.
- **Platform-isolation check:** The host gate's macOS-untouched and no-Apple-framework-in-GTK
  checks passed; macOS build evidence is absent.
- **Linux evidence:** [build record](BUILDING.md),
  [environment assessment](BUILD_ENV_OPTIONS.md), [Docker evidence](evidence/m01/docker/),
  [Flatpak evidence](evidence/m01/flatpak/).
- **macOS CI evidence:** UNVERIFIED; a separate CI lane is planned for M15.
- **Remaining risks:** Host GTK floors block the host build; GTK build/launch in the approved
  Flatpak lane, host runtime compatibility, and container tests remain unresolved.
- **Next task:** Produce GTK build and launch evidence in the approved Flatpak lane.

## How to resume

- Read the master plan in the Agent-Kit workspace: MASTER_PLAN.md (Agent-Kit workspace `docs/MASTER_PLAN.md`).
- Review the durable audit and status docs in `docs/background-media/`.
- Run the workspace gate script: verify-ghostty.sh (Agent-Kit workspace `scripts/verify-ghostty.sh`).
- Review the host baseline log: gate-full-baseline.log (Agent-Kit workspace `notes/m00/gate-full-baseline.log`).
- Find task reports and run records under `.orchestrator/runs/` in the Agent-Kit workspace.
