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

Expect physical memory, default Metal device information, device activity, and a process table filterable by name or PID. `--sample-gpu` takes a single native reading. `--sample-process-gpu` takes two readings one second apart and prints observed process GPU milliseconds per second and coverage. Quit the window with Command-Q. See Distribution for the Homebrew app bundle and remaining release work.

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

- [x] The development build adds a read-only llama.cpp inspector. Synthetic tests verify metadata and the exact loopback `GET /props` request without a model query. All 33 tests and the release build passed. A real llama.cpp server and the new tab still need a smoke test. Homebrew 0.1.0_1 includes GGUF and Ollama.

### Distribution

- GitHub repository visibility is public. The first [GitHub Pages workflow run](https://github.com/Digital-Defiance/MetalTask/actions/runs/43499738938) succeeded. The GitHub Pages URL redirects to the configured custom domain, where the site returned HTTP 200. GitHub had yet to issue the domain's HTTPS certificate. Check Settings → Pages for certificate status, then enable Enforce HTTPS and verify the secure URL.
- The [v0.1.0 source release](https://github.com/Digital-Defiance/MetalTask/releases/tag/v0.1.0) is published. The [public Homebrew formula](https://github.com/Digital-Defiance/homebrew-tap/blob/main/Formula/metaltask.rb) is on tap `main` at `c4ac122`. The local tap checkout at `/Volumes/Code/homebrew-tap` has the same formula.
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

## Runtime inspection handoff

The maintainer uses LM Studio. On 2026-11-13 its existing loopback server at `127.0.0.1:1234` returned five catalog entries and one loaded instance. The release-built development command below reported one loaded instance through MetalTask's own adapter. No credentials, model names, model downloads, inference requests, or server changes were needed.

```sh
cd /Volumes/Code/MetalTask
swift test
swift build -c release
swift run MetalTask --check-lm-studio
swift run MetalTask
```

- **LM Studio** — In **Loaded Models → LM Studio**, enter the local port and select **Check LM Studio**. The adapter reads native `GET /api/v1/models`, flattens only `loaded_instances`, and ignores downloaded-only catalog entries. It reports service-level model name, instance ID, architecture, quantization, configured context and KV-cache offload when available. The offload flag is a configuration value. The optional token is held in the view session and sent only to the selected loopback port. Redirects are refused. The CLI check uses port 1234 and prints only a count.
- **llama.cpp** — In **Loaded Models → llama.cpp server**, enter the port of an already-running single-model server. MetalTask sends unqualified `GET /props` without a model query, displays the configured filename basename, context, slots and sleep status, and ignores prompt and template fields. A synthetic server verified the exact request.
- **Ollama** — The v0.1.0 inspector was verified against a synthetic server and with Ollama absent. An existing real server with a loaded model is still needed for runtime verification.
- **GGUF** — Homebrew 0.1.0_1 includes the file picker. Verified v2/v3 fixtures in tests and a synthetic v3 file in the installed app. Real-world model files, split shards and other byte orders remain coverage work. Inspection is limited to one selected file.
- The development suite passed all 34 tests and the release build on the M4 Max. The LM Studio CLI was also verified against the real local service. UI checks for the two new tabs, LM Studio authentication, and a real llama.cpp server remain open. The public Homebrew formula still installs v0.1.0_1. The two new runtime adapters are on the development branch tip of `main` and are pending a new release tag and tap update.

## Next session · Verify and release the runtime adapters

1. Open the LM Studio tab in a development build and confirm the already-loaded instance appears. Check empty, unavailable and authenticated states where a test service or existing configuration permits. Keep model metadata attached to the service until a process PID and start time can be corroborated.
2. Check the llama.cpp tab with an existing single-model server, including sleep state if supported. Confirm a router or stopped server gives clear feedback. Try a representative real GGUF and one split shard if available.
3. After smoke testing, tag a new source release, fetch the exact GitHub archive and checksum, update `/Volumes/Code/homebrew-tap/Formula/metaltask.rb`, and verify a Homebrew upgrade. Preserve the existing Xcode requirement, the SwiftPM build arguments used under Homebrew, and the app bundle smoke test. Verify GitHub Pages HTTPS certificate status before enabling HTTPS enforcement.
4. Scope MLX metadata inspection using a selected config and shard metadata. Continue the two-workload window check, in-flight helper cancellation, sleep/wake, and telemetry validation on a second Apple Silicon generation and macOS 14 when available.

## Subsequent milestones

| Priority | Work | Acceptance |
| --- | --- | --- |
| P1 · Process table verification | Smoke-test the window, validate multi-client attribution and coverage on additional hardware and macOS versions. | The two-workload sequence is visible in the table and survives window reopen and wake without stale attribution. |
| P1 · Graphics footprint verification | Validate overhead, cancellation, and standard-user coverage across supported OS versions. | Denied, exited, timed-out, and unsupported cases remain distinguishable. Other rows and device polling keep updating. |
| P2 · Model details | Verify LM Studio and llama.cpp end to end, then add MLX inspection. | Fixture-tested bounded parsing and timeouts. Metadata source and PID confidence are visible. Models can appear at service level without guessing the runner. |
| P3 · Device diagnostics | Validate gpucap power, clock, temperature, and throttling sources on the support matrix. | Each displayed metric has a documented source, unit, and unavailable state. |
| P3 · Menu bar and polish | Add a menu-bar consumer, accessibility checks, and the performance soak. | Both views share one collector. Keyboard navigation and status labels work, and the measurements meet the validation gates in the spec. |
| P3 · Model details (later) | Add optional PyTorch MPS inspection and optional persistent history with longer-range charts. | Opt-in only, no inference from process names, documented retention limits, and the live five-minute buffer stays bounded. |
| P1 · Project hygiene | Verify README.md commands from a clean checkout. Review prior art (gputaskman, macmon, SiliconScope) and record what each exposes. Confirm trademark availability for the name. | README commands work from a clean checkout. A short prior-art note is in the repo. Name check is recorded. |
| P3 · Module split | Move model inspectors into a `ModelInspection` module and keep `MetalTelemetry` free of SwiftUI so it is reusable. | Targets build independently and `MetalTelemetry` has no UI imports. |
| P4 · Distribution | Package a macOS app, validate the hardware and OS matrix, sign, notarize, and verify installation on a clean machine. | Standard-user launch and graceful degradation on supported machines. Record exact supported configurations, setup commands, and remaining limits. |

As each milestone lands, update the current state with what shipped, the commands actually run, and the next executable task. Keep exact machine and OS results with telemetry validation evidence.
