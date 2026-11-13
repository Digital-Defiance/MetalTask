# MetalTask implementation handoff

## Start here

Work in `/Volumes/Code/MetalTask`. The configured origin is `https://github.com/Digital-Defiance/MetalTask.git`. Check `git status --short --branch` before editing. Read [SPEC.md](SPEC.md) for metric definitions, design decisions, and validation gates.

### Build and test

Use an Apple Silicon Mac with Xcode selected and a Swift 6 toolchain. The SwiftPM manifest targets macOS 14 and has no external package dependencies. Open `Package.swift` in Xcode or run these commands from Terminal as a standard user.

```sh
cd /Volumes/Code/MetalTask
git status --short --branch
xcode-select -p
swift --version
swift build
swift test
swift run MetalTask
```

The development executable opens a SwiftUI window. Expect physical memory and default Metal device information, or an unavailable state for the device. Quit with Command-Q. Use `swift build -c release` for the optimized executable. Signing and an installable app bundle are release work.

### Current state

- [x] Preserved the existing MIT license and added the product specification and handoff.
- [x] Added a Swift 6 package with the `MetalTelemetry` library and `MetalTask` SwiftUI executable. The window presents startup hardware metadata from Foundation and Metal.
- [x] Added two Swift Testing checks for missing-device behavior and agreement with system APIs.
- [x] On an Apple M4 Max running macOS 26.6.2 (25G83), Xcode 27.0 and Swift 6.4, `swift build`, `swift test` (two tests), and `swift build -c release` passed using a temporary SwiftPM scratch path.
- [x] A read-only `ioreg` probe on that Mac returned the candidate device fields and entries containing `accumulatedGPUTime`. This observation establishes field presence on one machine. Units, access outside this environment, and behavior under load still need validation.
- [ ] Visual smoke test pending. `swift run MetalTask` built and started the development process, but the window could not be inspected from the verification session. Confirm the window and its labels from a logged-in Terminal session.
- [ ] Live GPU activity, process rows, graphics-footprint sampling, model adapters, and app distribution are pending. macOS 14 is the deployment target and still needs runtime validation.

## Next session · Prove device utilization

1. Capture a standard-user sample before implementing the provider. These commands print only the candidate values. If a key is absent, record the chip, OS build, command, and observed absence. Keep full registry dumps local.

   ```sh
   sw_vers
   /usr/sbin/ioreg -r -c IOAccelerator -d 1 -w 0 |
     rg -o '"(Device Utilization %|Alloc system memory|In use system memory)"=[0-9]+'
   ```

2. Compare idle, load, and recovery with Activity Monitor → Window → GPU History. Use a repeatable bounded Metal workload with a known allocation and an explicit stop. Record range, duration, OS, chip, and whether the driver fields follow the workload. Treat allocation units and scope as separate questions.
3. Add a small IOKit-backed device provider under `Sources/MetalTelemetry`. Read the property in-process, manage IOKit object lifetimes, and keep decoding separate from enumeration. Validate service selection and return per-field availability. Start by exposing device utilization only. Add allocation bytes once the validation supports it.
4. Add Swift Testing fixtures for a valid zero, typical load, missing or wrongly typed data, out-of-range values, and ambiguous device selection. Run `swift test`, then exercise the provider on hardware. This milestone is done when the provider follows idle/load/recovery and unsupported data returns an explicit unavailable reason without disabling hardware metadata.

## Subsequent milestones

| Priority | Work | Acceptance |
| --- | --- | --- |
| P1 · Live window | Add a cancellable collector, bounded history, and Swift Charts. | One poll loop, explicit stale and unavailable states, gaps where data is absent, and sampling stops when all consumers close. |
| P2 · Process attribution | Discover PIDs and start times. Probe AGX clients and validate units and identity before computing deltas. Add a sortable and searchable process table. | Controlled single- and multi-client loads identify the right process. Fixtures cover warm-up, reset, client churn, PID reuse, and overlapping work. |
| P2 · Graphics footprint | Validate `footprint` on supported OS versions with standard-user access. Wire it in with bounded, slower sampling if its output is usable. | Denied, exited, timed-out, and unsupported cases remain distinguishable. Other rows and device polling keep updating. |
| P3 · Model details | Implement opt-in Ollama, then MLX and llama.cpp/GGUF inspection. | Fixture-tested bounded parsing and timeouts. Metadata source and PID confidence are visible. Models can appear at service level without guessing the runner. |
| P3 · Menu bar and polish | Add a menu-bar consumer, accessibility checks, and the performance soak. | Both views share one collector. Keyboard navigation and status labels work, and the measurements meet the validation gates in the spec. |
| P4 · Distribution | Package a macOS app, validate the hardware and OS matrix, sign, notarize, and verify installation on a clean machine. | Standard-user launch and graceful degradation on supported machines. Record exact supported configurations, setup commands, and remaining limits. |

As each milestone lands, update the current state with what shipped, the commands actually run, and the next executable task. Keep exact machine and OS results with telemetry validation evidence.
