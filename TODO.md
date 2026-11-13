# MetalTask implementation handoff

## Start here

Work in `/Volumes/Code/MetalTask`. The configured origin is `https://github.com/Digital-Defiance/MetalTask.git`. Check `git status --short --branch` before editing. Read [SPEC.md](SPEC.md) for metric definitions, design decisions, and validation gates.

On 2026-11-13 the required checkout was on local bootstrap `3bad019`, with its tracking ref still at `85c846f`. GitHub's `main` was independently verified at `8b427e8`, a parallel bootstrap from the same initial project. The original “Build Swift GPU Monitor” ChatGPT discussion and both Codex handoffs agree on a native, process-oriented Swift app, a reusable telemetry library, and validation before displaying new metrics. The continuation builds on the local `SystemSnapshot` implementation and brings over the remote README's setup and acknowledgments. The remote bootstrap calls its equivalent API `SystemOverview`. Before publishing, fetch and integrate GitHub's branch, review the overlapping docs and startup APIs, and preserve both histories.

### Build and test

Use an Apple Silicon Mac with Xcode selected and a Swift 6 toolchain. The SwiftPM manifest targets macOS 14 and has no external package dependencies. Open `Package.swift` in Xcode or run these commands from Terminal as a standard user.

```sh
cd /Volumes/Code/MetalTask
git status --short --branch
xcode-select -p
swift --version
swift build
swift test
swift build -c release
swift run MetalTask --sample-gpu
swift run MetalTask --sample-process-gpu
swift run MetalTask
```

Expect physical memory, default Metal device information, device activity, and a process table filterable by name or PID. `--sample-gpu` takes a single native reading. `--sample-process-gpu` takes two readings one second apart and prints observed process GPU milliseconds per second and coverage. Quit the window with Command-Q. Signing and an installable app bundle are release work.

### Current state

- [x] The Swift 6 bootstrap supplies startup hardware metadata through `SystemSnapshot` and preserves the MIT license.
- [x] `DeviceActivitySample` matches the default Metal device by registry ID and reads the activity percentage in-process. The window samples device and process activity on a serial worker about once per second. Zero remains a valid reading.
- [x] On an Apple M4 Max running macOS 26.6.2 (25G83), Xcode 27.0 (27A266a), and Swift 6.4, debug and release builds and all 30 tests passed. Tests cover telemetry, subprocess cleanup, history, Ollama transport, and GGUF metadata.
- [x] Standard-user device utilization followed a bounded Metal workload on this M4 Max. The Metal device and `IOAccelerator` reported the same registry ID. See the results below.
- [x] `ioreg` exposed the candidate allocation keys and AGX `accumulatedGPUTime` entries. `footprint -h` advertised PID and JSON options. Units, graphics accounting, and access coverage still need validation.
- [x] Added a native AGX client sampler and sortable, filterable SwiftUI process table. Two overlapping workloads were attributed to the correct PIDs through the Terminal probe, including after the first workload exited.
- [x] A temporary app bundle containing the release executable opened the SwiftUI window on the M4 Max. Verified changing device activity, observed process rates, the partial-coverage status, filtering by process name, and sorting by PID.
- [x] Verified populated graphics-footprint values sorted largest first in a temporary release app bundle. Closing and reopening returned the process rows to baseline and the footprint cells to pending.
- [ ] Verify the two-workload sequence in the window and directly observe polling and in-flight helper cancellation on close.
- [x] Added a separate graphics-footprint reader and sortable column. Standard-user probes read the controlled same-user allocation and macOS limited access to protected processes.
- [x] Moved activity and footprint collection into a shared actor used by the window and versioned Terminal snapshots. On the M4 Max a before/load comparison showed a 35 percentage-point increase and correctly identified the new workload row. The capture included the workload's positive GPU rate and a footprint observation.
- [x] Added a five-minute Swift Charts view using the existing activity poll. Verified a live trace above the process table and a fresh single point on reopening in a temporary release app bundle. Verified that JSON snapshots still export schema 1.
- [x] Added an opt-in Ollama inspector under **Loaded Models**. Verified that the app displays the unreachable state on this Mac and renders all supported metadata from a one-shot loopback fixture. The test suite uses ephemeral loopback listeners and needs no Ollama installation or downloaded models.
- [x] Added a GGUF file picker and bounded metadata reader. Synthetic v2/v3 files exercise metadata, tokenizer arrays, and tensor offsets. The Homebrew-installed app opened a synthetic v3 file and showed its name, architecture, file type, context length, tensor count, and version. Real model-file compatibility remains open.

### Distribution

- GitHub repository visibility is public. The first [GitHub Pages workflow run](https://github.com/Digital-Defiance/MetalTask/actions/runs/43499738938) succeeded. The GitHub Pages URL redirects to the configured custom domain, where the site returned HTTP 200. GitHub had yet to issue the domain's HTTPS certificate. Check Settings → Pages for certificate status, then enable Enforce HTTPS and verify the secure URL.
- The [v0.1.0 source release](https://github.com/Digital-Defiance/MetalTask/releases/tag/v0.1.0) is published. The [public Homebrew formula](https://github.com/Digital-Defiance/homebrew-tap/blob/main/Formula/metaltask.rb) is on tap `main` at `4c144a7`. The local tap checkout at `/Volumes/Code/homebrew-tap` has the same formula.
- Verified `brew install --build-from-source digital-defiance/tap/metaltask`, `brew test digital-defiance/tap/metaltask`, `metaltask --sample-gpu`, and launch from the installed app bundle. Homebrew installed `0.1.0_1`. The formula builds and ad hoc signs the app locally. Developer ID signing, notarization, and macOS 14 runtime validation remain release work.
- [ ] The macOS 14 deployment target still needs runtime validation. Additional Apple Silicon generations, wake behavior, broader process and footprint coverage, model adapters, and distribution remain open.

## Device utilization validation

From the repository root, use a standard-user Terminal. Sample before, during, and after the workload, and compare with Activity Monitor → Window → GPU History. Keep full registry dumps local.

```sh
swift build
validation_dir=$(mktemp -d)
swiftc -O Tools/GPUValidationWorkload.swift -o "$validation_dir/gpu-workload"
metaltask_bin="$(swift build --show-bin-path)/MetalTask"
sample_gpu() {
  for i in 1 2 3 4 5 6 7 8; do
    date +%T
    "$metaltask_bin" --sample-gpu
    /usr/sbin/ioreg -r -c IOAccelerator -d 1 -w 0 |
      rg -o '"Device Utilization %"=[0-9]+'
    sleep 1
  done
}
sample_gpu
"$validation_dir/gpu-workload" &
workload_pid=$!
sleep 2
sample_gpu
wait "$workload_pid"
sample_gpu
```

The workload uses a 4 MiB shared Metal buffer, submits for 12 seconds, and waits for each command to finish. In two runs on the M4 Max, the native provider held at 88–92% after ramp-up and fell to 23% one second after the first post-exit sample in both runs. Ambient readings varied, including an isolated 74% before the first run and zero after the second. Sequential `ioreg` readings showed peaks of 90–94% during load, with frequent zeroes between them. The samples do not establish equivalence at each timestamp. Activity Monitor GPU History showed a rise and fall on a separate run. Driver allocation units and scope remain open.

`bgpucap 0.1.4` also drove the native and `ioreg` readings to 100% with `bgpucap gpuexercise --mode load --percent 85 --seconds 16 --metrics basic`. Its summary reported 0%, and both registry readers stayed at 100% through the first eight post-exit samples. The synchronized Swift workload above supplies the recovery evidence. For the process milestone, review gpucap's `src/gpu_proc.rs` at `76cb352` for creator and `AppUsage` discovery. Verify time units independently and retain per-client identities across samples.

## Process attribution validation

In the same Terminal session as the device setup above, run two staggered copies of the 12-second workload and filter the sampler to those PIDs.

```sh
"$validation_dir/gpu-workload" &
first=$!
sleep 4
"$validation_dir/gpu-workload" &
second=$!
sample_processes() {
  "$metaltask_bin" --sample-process-gpu |
    awk -v a="$first" -v b="$second" 'NR == 1 || $1 == a || $1 == b || /^Some/'
}
sample_processes
sample_processes
wait "$first"
sample_processes
wait "$second"
sample_processes
```

On the M4 Max the two workloads each reported 458–505 GPU ms/s while both ran. After the first exited, its row disappeared and the survivor reported 899 GPU ms/s. The second row also disappeared at exit. The host reported partial coverage for other clients. In a separate single-process run, six registry intervals read 895–955 GPU ms/s. The workload's public Metal command-buffer timestamps averaged 843 GPU ms/s over the full run. This supports the nanosecond scale. The intervals and accounting scopes differ, and neither result establishes per-engine occupancy. The current reader discards intervals with changed counter record counts or rollback. Stability of multi-record `AppUsage` ordering and accounting still needs hardware evidence.

## Graphics footprint validation

From the repository root in a standard-user Terminal:

```sh
swift build
validation_dir=$(mktemp -d)
swiftc -O Tools/GraphicsFootprintWorkload.swift -o "$validation_dir/footprint-load"
metaltask_bin="$(swift build --show-bin-path)/MetalTask"
"$validation_dir/footprint-load" &
pid=$!
"$metaltask_bin" --sample-graphics-footprint "$pid"
sleep 9
"$metaltask_bin" --sample-graphics-footprint "$pid"
sleep 12
"$metaltask_bin" --sample-graphics-footprint "$pid"
"$metaltask_bin" --sample-graphics-footprint 1
wait "$pid"
"$metaltask_bin" --sample-graphics-footprint "$pid"
```

On the M4 Max, the raw report described byte units and exposed `IOAccelerator (graphics)` and `Owned physical footprint (unmapped) (graphics)`. With a GPU-touched 64 MiB private buffer, their combined dirty charge reached 235,356,160 bytes while held and was 67,272,704 bytes in one post-release snapshot. Another run of the MetalTask reader returned 81,920 bytes before the hold, 67,272,704 while held, and 163,840 after release. The measured charge can vary by run and can outlive the allocation. The standard-user reader returned `permissionDenied` for PID 1 and `processChanged` for an exited or nonexistent PID. Keep raw reports local.

## Snapshot comparison

```sh
swift run MetalTask --snapshot-json > before.json
# Start or change the workload.
swift run MetalTask --snapshot-json > after.json
swift run MetalTask --compare before.json after.json
```

Both captures must come from the same boot session. For a footprint comparison on one observed process, pass `--footprint-pid "$pid"` after `--snapshot-json` in both commands. The default capture probes at most four rows and may skip quieter GPU clients. The output contains local process names and identities. The comparison reports first observed and no longer observed rows, with a dash when the same metric could not be compared across both captures.

Verified on the M4 Max with `Tools/GraphicsFootprintWorkload.swift`: a targeted capture during the hold recorded 67,272,704 bytes. A second capture after release recorded 163,840 bytes for the same process identity. The comparison reported a decrease of 67,108,864 bytes (64 MiB). The updated window showed fresh activity baselines and pending footprint cells on reopen, then populated both types of reading.

## Next session · Start llama.cpp runtime inspection

1. Probe a configured local llama.cpp server for runtime-reported metadata when available. Use the Ollama adapter's loopback and timeout constraints. A real Ollama smoke test remains open and can wait until an existing service and loaded model are available.
2. Exercise GGUF inspection with representative real files if available, including one shard of a split model. Synthetic fixtures cover v2 and v3 metadata, unsupported versions, truncation, length limits, and invalid offsets.
3. Continue hardware validation in parallel with feature work. Verify the two-workload sequence in the window, directly observe close while `footprint` is in flight, and check the chart after sleep/wake. Repeat telemetry checks on a second Apple Silicon generation and macOS 14 where available.

## Subsequent milestones

| Priority | Work | Acceptance |
| --- | --- | --- |
| P1 · Process table verification | Smoke-test the window, validate multi-client attribution and coverage on additional hardware and macOS versions. | The two-workload sequence is visible in the table and survives window reopen and wake without stale attribution. |
| P1 · Graphics footprint verification | Validate overhead, cancellation, and standard-user coverage across supported OS versions. | Denied, exited, timed-out, and unsupported cases remain distinguishable. Other rows and device polling keep updating. |
| P2 · Model details | Extend the opt-in Ollama inspector with llama.cpp/GGUF and MLX inspection. | Fixture-tested bounded parsing and timeouts. Metadata source and PID confidence are visible. Models can appear at service level without guessing the runner. |
| P3 · Device diagnostics | Validate gpucap power, clock, temperature, and throttling sources on the support matrix. | Each displayed metric has a documented source, unit, and unavailable state. |
| P3 · Menu bar and polish | Add a menu-bar consumer, accessibility checks, and the performance soak. | Both views share one collector. Keyboard navigation and status labels work, and the measurements meet the validation gates in the spec. |
| P3 · Model details (later) | Add optional PyTorch MPS inspection and optional persistent history with longer-range charts. | Opt-in only, no inference from process names, documented retention limits, and the live five-minute buffer stays bounded. |
| P1 · Project hygiene | Verify README.md commands from a clean checkout. Review prior art (gputaskman, macmon, SiliconScope) and record what each exposes. Confirm trademark availability for the name. | README commands work from a clean checkout. A short prior-art note is in the repo. Name check is recorded. |
| P3 · Module split | Move model inspectors into a `ModelInspection` module and keep `MetalTelemetry` free of SwiftUI so it is reusable. | Targets build independently and `MetalTelemetry` has no UI imports. |
| P4 · Distribution | Package a macOS app, validate the hardware and OS matrix, sign, notarize, and verify installation on a clean machine. | Standard-user launch and graceful degradation on supported machines. Record exact supported configurations, setup commands, and remaining limits. |

As each milestone lands, update the current state with what shipped, the commands actually run, and the next executable task. Keep exact machine and OS results with telemetry validation evidence.
