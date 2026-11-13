# MetalTask implementation handoff

Updated 2026-11-13. Start here when resuming. The telemetry definitions and compatibility rules are in [SPEC.md](SPEC.md).

## Current status

- [x] Inspected `Digital-Defiance/MetalTask`. The starting tree at `85c846f` held only Digital Defiance's MIT license, which was preserved.
- [x] Added a dependency-free Swift 6 package, `MetalTelemetry` library, SwiftUI window, and a test of the no-Metal-device path.
- [x] Verified `swift build` and `swift test` on arm64 macOS 26.6.2 with Xcode 27.0 (27A266a) and Swift 6.4. One Swift Testing test passed. `swift run MetalTask` started without a reported launch error. The window and macOS 14 runtime behavior still need a manual check.
- [x] Probed IORegistry on an arm64 host running macOS 26.6.2 (25G83). The command output contained the candidate device statistics keys and AGX client counter and creator keys. This establishes key presence on one host. No workload response, units, cross-user access, or native IOKit collector behavior was verified.
- [x] Checked `footprint -h` on that host. It advertises PID selection and JSON output to a file. Graphics category layout and readable process coverage still need verification.
- [ ] Live collection, ranked process view, graphics footprint, model inspection, compatibility matrix and release artifacts remain open.

## Resume in order

1. From a fresh clone, check `git status --short --branch` and `git log -5 --oneline` before editing. Run the baseline build and test below. Record OS build, Apple Silicon generation and Swift version.
2. Implement **M1**, the device-wide collector. Keep the diff focused on typed parsing, native device sampling and the independent unavailable path. Use sanitized fixture dictionaries first. Probe the host and compare native samples against `ioreg` under a reproducible workload before adding a chart or allocation label.
3. Record results and the exact next open checkbox here before ending the session. If hardware or keys block a metric, preserve the existing app, record which OS and source failed, and continue with the fixture-driven paths.

### Baseline commands

Run from the repository root with Xcode selected. The deployment target is macOS 14. Only claim versions actually tested.

```sh
xcode-select -p
xcodebuild -version
swift --version
sw_vers
swift build
swift test
swift run MetalTask
```

The development app should open a window with physical memory, the default Metal device if available, and an explicit unavailable state for live GPU activity. To check source changes before committing, run `git diff --check` and `git diff --cached --check`.

## M1 · P0 · Device telemetry

- [ ] Probe without `sudo`. Record device identity, keys, value types, and behavior on idle, load, stop and wake. Compare native IOKit with the command probes. Verify driver allocation units with a bounded controlled allocation before exposing that metric.
- [ ] Implement a typed `IOAccelerator` reader and parser in `MetalTelemetry`. Keep device selection explicit and handle absent dictionaries, invalid numbers and ambiguous device matches.
- [ ] Add a one-second cancellable sampling loop and short bounded history. Show latest device activity and optional chart with gaps. Preserve the bootstrap's static device and memory view when the provider fails.
- [ ] **Accept when** a bounded Metal workload raises the device reading relative to idle across repeatable runs, the reading drops when the workload stops, and no-provider and bad-schema fixtures render as unavailable. Record the OS/chip, workload and sample timings. No broad compatibility claim from one host.

Run the following locally. AGX registry output can include process identifiers. Keep raw output off GitHub and out of fixtures.

```sh
/usr/sbin/ioreg -a -r -c IOAccelerator -d 1
/usr/sbin/ioreg -a -r -c AGXDeviceUserClient -d 1
/usr/bin/footprint -h
```

Create a small local Metal workload with two modes: a 20 s compute loop and a bounded graphics allocation, starting at 64 MiB. Touch the allocation on the GPU, hold it long enough for a footprint poll, and release it. Capture 10 s idle, 20 s load and 10 s recovery with matching timestamps. Record the test process's PID, app-owned Metal allocation and timing locally to evaluate the signals. Use Activity Monitor GPU History as a qualitative comparison, since averaging windows can differ. Keep the workload source or exact reproduction commands with the validation notes.

## M2 · P0 · Process GPU activity

- [ ] Enumerate AGX user clients, validate counter units and creator mapping, and resolve PID plus process start time. Capture two snapshots and diff by stable client ID and process identity. Define coverage and display units before choosing UI labels.
- [ ] Add a sortable process table and selection details. Distinguish known idle, detected client with no valid rate, stale data, and unavailable attribution. Maintain the device view with an independent process-provider failure.
- [ ] Test multiple clients per PID, duplicate records, partial reads, first sample, counter resets, no delta, overlapping GPU time, long interval, sleep/wake, process exit and reused PID. Confirm no false zero or rate spikes on those paths.
- [ ] **Accept when** the controlled Metal process appears and changes with the workload, a concurrent workload gives independently visible activity where readable, and a launch/exit sequence leaves no stale attribution attached to a new process. If the driver does not expose stable identities or a defensible rate, ship the device view with explicit limited process capability.

## M3 · P1 · Graphics footprint and beta hardening

- [ ] Probe a same-user target and a controlled denied target. For JSON, create a private temp directory with `mktemp -d`, then run `/usr/bin/footprint --pid <PID> --json <temp-directory>/footprint.json` after substituting a real PID and path. Remove the temp directory after inspection. Record only redacted schema and measurements.
- [ ] Confirm what dirty graphics categories account for on the controlled allocation. Distinguish no category, denied, process gone, timeout, malformed output and complete data. Use a bounded async command runner with PID revalidation and scheduler limits.
- [ ] Test recorded schemas and fake command outcomes, including concurrent refresh, target exit, PID reuse during measurement, cancellation, timeout, cleanup and oversized output. Keep missing graphics bytes separate from total process memory.
- [ ] Profile five minutes of idle sampling and five minutes with a sustained workload. Record CPU, memory, refresh rate and command counts. As starting targets, aim for under 2% CPU on one core on a reference Mac at idle and no unbounded memory/history growth. Footprint may be deferred or throttled if it exceeds the budget.
- [ ] **Accept when** standard users get defensible graphics footprint readings where validated, visibility limits are clear, and a failing or slow footprint probe leaves device and process updates responsive.

## M4 · P1 · App bundle and public beta

- [ ] Add a macOS app target or reproducible packaging step for the existing package executable. Set a maintainer-owned bundle identifier, version and build number. Validate the bundled build as a standard user before claiming telemetry support.
- [ ] Add macOS CI with a pinned Swift 6-capable Xcode version for build and fixture tests. Maintain a manual compatibility matrix across two Apple Silicon generations, the minimum macOS release and the current release. Raise the floor if the older OS cannot be supported or verified for the release.
- [ ] Sign the arm64 app with Developer ID Application and hardened runtime. Package for notarization and distribute a stapled app or DMG via GitHub Releases. Use CI secret storage or a Keychain profile for credentials. Never commit signing material.
- [ ] Validate the final app with `codesign --verify --deep --strict --verbose=2 MetalTask.app`, `xcrun stapler validate MetalTask.app` if stapling the app, and `spctl --assess --type execute --verbose=2 MetalTask.app`. Use the corresponding stapler check for a stapled DMG. Download the release on a clean Mac, verify Gatekeeper, and repeat idle, load and denied-capability smoke checks.
- [ ] **Accept when** a fresh standard-user install works on the published matrix, the artifact includes MIT and any applicable third-party notices, and the release notes list verified and unavailable features. Publish a SHA-256 checksum for the final artifact. If signing credentials are unavailable, keep source builds usable and record the release blocker.

## M5 · P2 · Model inspection

- [ ] Ollama first. Implement opt-in loopback `/api/ps` with version-tolerant fixtures for absent fields, no server, multiple models and mismatched identities. Verify redirect rejection, proxy bypass, timeout and response cap. Accept when server-reported model fields appear without claiming a PID join the evidence cannot establish.
- [ ] MLX second. Prototype an opt-in reporter or user-selected metadata with a known sample model. Accept when runtime evidence, configuration and allocator metrics are labeled independently and ambiguous cases show model unknown.
- [ ] llama.cpp and GGUF next. Read only bounded metadata from user-selected files. Test truncated, oversized, unsupported and split-model inputs. Accept when model metadata remains distinct from observed process activity and runtime offload.
- [ ] Add weights and KV estimates only for explicitly supported layouts. Test arithmetic and unknown fields against small reference cases, and verify the UI labels runtime-reported, estimated and OS-observed bytes independently.

## Decisions and blockers

| Decision | Default and trigger to revisit |
| --- | --- |
| Upstream | Reference and credit gputaskman. Use labeled fixtures for initial UI work. Add attribution notices before any source translation. Revisit a development-only adapter if sanitized fixtures are insufficient. |
| Unstable registry data | Disable individual metrics when missing or unverifiable. Revisit after collecting redacted fixtures and workload evidence on the affected OS. |
| Elevated access | Ship standard-user collection. Revisit privilege only as a separately scoped design after measuring the coverage gap and agreeing on a concrete use case. |
| Target OS | macOS 14 is a build target. Hardware availability and tests determine the published support floor. |
| Distribution | Developer ID, bundle identifier and release credentials are needed for public distribution. No signing credentials were checked during bootstrap. |
| Model-to-process join | Keep runtime-level models visible separately until a verified PID and start-time association exists. Unknown is a supported outcome. |
