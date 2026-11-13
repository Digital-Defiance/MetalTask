# MetalTask specification

## Product and scope

MetalTask is an MIT-licensed macOS GPU task manager for Apple Silicon. It answers three questions in order.

1. Is the GPU busy?
2. Which visible processes are submitting GPU work, and how much graphics memory does macOS attribute to them?
3. For a recognized local inference runtime, which models are loaded and what can it report about their memory?

Build a native Swift 6 application using SwiftUI, Swift Charts, and Swift concurrency. Use macOS 14 as the initial deployment target. Treat it as a build target until the hardware and OS matrix is verified. The first usable release has a live device summary, a process table, and explicit status for each metric. Process control, exact per-engine attribution, and Intel or external GPU support are outside the first release, but keep the providers replaceable so those targets are not ruled out later. Model inspection and the menu-bar view follow the monitoring baseline.

The application is MetalTask, the reusable Swift library is `MetalTelemetry`, and the tagline is “Know what's running on your GPU.” Development uses [Digital-Defiance/MetalTask](https://github.com/Digital-Defiance/MetalTask). Check trademark availability before distribution. The GPU-first workflow centers on which applications use the GPU, how much memory they hold, and which inference workloads are active. Show loaded model, quantization, context length, and estimated weight and KV-cache sizes when evidence supports them.

Design principles: build an independent native application, not a Python fork. Keep `MetalTelemetry` reusable by other Swift projects and independent of SwiftUI. Make GPU telemetry, model inspectors, and the UI independent modules. Distinguish measured, estimated, and unavailable values everywhere. Degrade gracefully under macOS permission restrictions.

Prior art to review for overlap and differentiation: gputaskman (Python, terminal UI, macOS backend in `macos.py`), macmon (Rust, GPU, power, temperatures, process statistics, JSON and Prometheus output), and SiliconScope (native SwiftUI Apple Silicon monitor with GPU, Neural Engine, memory bandwidth, and AI workload monitoring). Record what each exposes and which sources it uses before duplicating work.

The project draws inspiration from Scott Hanselman and the [gputaskman contributors](https://github.com/shanselman/gputaskman#macos-apple-silicon). Use their macOS notes as a comparison source. MetalTask is independently implemented with no Python runtime dependency. Preserve applicable notices if upstream code is adapted in the future. Reference gputaskman rather than forking it, credit Scott Hanselman and the contributors in an Acknowledgments section of the README, and treat its macOS backend as a technical reference and validation baseline, not a dependency. If any substantial upstream code is translated to Swift, retain its MIT copyright and license notice. Share general-purpose findings back upstream where useful.

[Digital Defiance's gpucap](https://github.com/Digital-Defiance/gpucap) is a development reference for device counters and AGX client discovery. Its `bgpucap gpuexercise` command can generate GPU load. The Swift app reads IORegistry directly and has no runtime dependency on the CLI. Its GPU utilization report shares the candidate driver source, so use Activity Monitor as the additional qualitative comparison.

### Windows and Linux workflows on Apple Silicon

Use gputaskman's Windows and Linux investigation workflow as the product reference. A user should be able to find the busiest visible GPU process, inspect the evidence for its model and allocations, and compare what changed after loading a model or adjusting context. [Feature overview](https://github.com/shanselman/gputaskman#what-you-get) · [Snapshot comparison](https://github.com/shanselman/gputaskman#comparing-snapshots)

| Workflow | MetalTask implementation |
| --- | --- |
| Rank GPU workloads | Sort visible processes by observed GPU time or OS-attributed graphics footprint. Keep coverage visible. |
| Explain model memory | Inspect opt-in Ollama first, then llama.cpp and GGUF, then MLX. Show the evidence for model identity, weights, KV-cache estimates, and runtime-reported buffers where available. |
| Compare before and after | Export versioned JSON from the same collector as the UI. Compare captures within one boot session and on the same accelerator. Match processes by PID and start time, report changes in visibility, and skip unavailable metrics. Keep runtime-reported values and estimates out of OS counter totals. |
| Diagnose hardware behavior | Validate device power, clocks, temperature, and throttling using gpucap as a reference. Require an applicable Apple Silicon source before exposing dedicated VRAM spill, PCIe throughput, or per-process engine splits. [gpucap metrics](https://github.com/Digital-Defiance/gpucap#metrics) |

## Telemetry sources

| Metric | Source and availability | Display contract |
| --- | --- | --- |
| Default GPU name, unified-memory flag, recommended working set | Public Metal device properties | Available in the bootstrap. The working set is a performance recommendation, with no implication about currently free memory. [Apple Metal documentation](https://developer.apple.com/documentation/metal/mtldevice/recommendedmaxworkingsetsize) |
| Installed physical memory | `ProcessInfo.physicalMemory` | Label as system physical memory. It is shared by CPU and GPU on Apple Silicon. |
| Device utilization | `IOAccelerator` registry service for the default Metal device, `PerformanceStatistics` → `Device Utilization %` | Label as device activity. Preserve observed values in 0–100, including zero. Show an unavailable reason when the source fails. The driver's averaging interval is unspecified. See [TODO.md](TODO.md) for hardware evidence. |
| Device GPU allocations | Candidate `Alloc system memory` in the same dictionary | Label as driver-reported GPU allocations once byte units and semantics are verified. Keep any `In use system memory` observation separate until its meaning is established. |
| Per-process GPU activity | `AGXDeviceUserClient` entries under the matched accelerator, with creator PID and `AppUsage.accumulatedGPUTime` | Report observed GPU milliseconds per elapsed second with partial coverage and unavailable states. The nanosecond interpretation is consistent with the M4 Max timing check. Compatibility and counter semantics still need broader validation. |
| Process names and lifetimes | SDK-declared `libproc` calls for PID and start time, with `NSWorkspace` for app names and icons | Include background processes when visible. Represent exited or inaccessible PIDs without misattributing metrics. |
| Process graphics footprint | Standard-user `/usr/bin/footprint` JSON probe for the sum of dirty bytes in categories ending in ` (graphics)` | A slower, permission-dependent OS accounting value that can include cached and driver allocations. Missing categories, unreadable processes, timeouts, and unsupported reports have explicit states. RSS and general process footprint may be shown separately with their own labels. |

IOKit provides documented registry reads. Service classes, driver dictionaries, individual keys, units, and access rules are implementation details that can vary with chip and OS. Isolate them in replaceable providers and check types, ranges, and units before conversion. The current reader matches the default Metal device's registry ID and requires the matched service to conform to `IOAccelerator`. If it cannot establish that match, it withholds the reading. Metal's `currentAllocatedSize` is useful for a test workload's own resources. Its API does not promise whole-system or cross-process accounting. [Apple IOKit registry reads](https://developer.apple.com/documentation/iokit/1514293-ioregistryentrycreatecfproperty), [Metal registry ID](https://developer.apple.com/documentation/metal/mtldevice/registryid), [Apple Metal allocation counter](https://developer.apple.com/documentation/metal/mtldevice/currentallocatedsize), [gputaskman macOS observations](https://github.com/shanselman/gputaskman#macos-apple-silicon)

Physical memory, Metal's working-set recommendation, driver allocation accounting, graphics footprint, and runtime-reported memory describe different scopes. Keep these as separate byte metrics. Shared pages, allocations versus residency, and incomplete visibility prevent a reliable reconciliation by summing process rows. Use consistent byte formatting with units and never label the shared pool as dedicated VRAM.

## Collection and data model

`MetalTelemetry` owns typed values, native source adapters, decoding, and sampling. It has no SwiftUI dependency. `SystemSnapshot.capture()` supplies startup metadata. The window and snapshot command use the same actor-based collector for timestamped device readings, per-client baselines, and footprint observations. The live window ties activity and footprint polling to its view task. Each window session has its own in-memory device history. Keep future runtime adapters independent from both the SwiftUI app and OS collection.

- Snapshot schema 1 uses Unix-second timestamps, the macOS boot-session identifier, the device registry ID, and process PID plus start time. The Terminal export captures activity over a one-second interval and probes footprint for up to four rows or for one specified observed PID. Footprint carries its own observation time and freshness. Comparison omits deltas for stale or missing footprint and for partial or missing per-process activity. A missing process row means it was outside the observed set for that capture.
- The live chart retains up to 300 readings from the last five minutes using a continuous monotonic clock. It shows a fixed 0–100% scale, preserves zero, and breaks the line at unavailable readings, accelerator changes, and intervals longer than 2.5 seconds. Window reopening starts a new history. Schema 1 snapshots contain the current device reading.

- Each periodic snapshot carries an observation time and per-metric source and scope. Store bytes as `UInt64`. Represent utilization as percent in a dedicated field.
- Track quality (measured, derived, estimated) separately from availability (fresh, stale, unavailable). Give unavailable readings a reason such as warming up, access denied, unsupported schema, ambiguous device, or source error. A stale reading carries its last observation time and can never become a fresh zero.
- Keep client baselines keyed by registry entry identity and process identity (PID plus start time). Normalize only validated deltas by actual monotonic elapsed time. Reset affected baselines on client turnover, PID reuse, counter rollback, sleep/wake, or excessive gaps. A disappearing client must not subtract from surviving clients' deltas. Mark partial coverage when appropriate. If overlap makes summed client rates unsuitable as a percentage, use GPU-time rate with explicit units. Process rates need not add up to the device reading.
- Use an actor for polling state and serialize each source's reads. Start with one device sample per second and bound the in-memory history to five minutes. Optional persistent historical recording, with longer-range charts, is a later milestone. It needs its own retention limit, opt-in, and sanitized storage, and must not change the bounded live buffer. Skip missed ticks rather than queueing reads. Put slow or blocking OS probes on a bounded worker queue off the main actor and publish immutable, sendable snapshots to the main-actor view model. Cancel polling when the last consumer disappears.
- The window schedules one graphics-footprint probe at a time, separately from GPU activity, with at least two seconds between probes. A process is eligible for refresh after 15 seconds, or 60 seconds after a denial. Readings older than 30 seconds are marked stale. The reader uses a fixed executable, a private temporary directory, size checks, and a three-second timeout. It rechecks PID and start time and kills and reaps the helper on timeout or cancellation.

## Interface and permissions

The current main window shows the latest device reading and five-minute activity chart above a sortable process table with name and PID filtering, activity coverage, and graphics footprint. The chart provides an accessible summary of the observed range. Sort unknown numeric values after observed values in either direction. The detail panel later shows model metadata and confidence of attribution. A menu-bar view can reuse the same collector once sampling overhead and lifecycle are verified.

Baseline monitoring runs as a standard user with no privileged helper, blanket disk access, or task-port access. Treat a denied graphics or process probe as a row-level limitation. Validate own-process, same-user, cross-user, and protected process behavior independently. An unsandboxed build still encounters macOS protections. Avoid scanning other apps' private containers, process environments, and unrelated files. Keep diagnostic fixtures sanitized and omit paths, account names, and prompts from normal logs.

The distribution milestone creates a signed macOS app bundle for direct Developer ID distribution with hardened runtime and notarization. The development SwiftPM executable is the initial entry point. Evaluate Mac App Store sandbox compatibility separately before making distribution commitments. [Apple distribution comparison](https://developer.apple.com/macos/distribution), [Apple notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Model inspection roadmap

| Stage | Evidence and limits |
| --- | --- |
| Ollama | The Loaded Models sheet makes one request when the user selects **Check Local Ollama**. It uses `GET /api/ps` on `127.0.0.1:11434` with a three-second timeout, a 256 KiB response limit, and redirects disabled. It displays model, digest, quantization, context length, and runtime-reported sizes when present. Models belong to the service until independent evidence links a runner PID. [Ollama API](https://docs.ollama.com/api/ps) |
| MLX | Support a user-selected MLX model directory or an opt-in adapter for a known runtime such as MLX LM. Read bounded config and shard metadata for architecture and quantization. A directory or process name alone cannot establish that the weights are loaded. [MLX LM](https://github.com/ml-explore/mlx-lm) |
| llama.cpp and GGUF | The file picker reads declared name, architecture, context length, GGUF file type, tensor count, and shard count from a selected little-endian GGUF v2 or v3 file. It bounds the header to 32 MiB, checks tensor offsets and arithmetic, skips tokenizer arrays, and leaves tensor contents unread. Each inspection covers one file. Future runtime inspection can use a configured loopback server and read-only endpoints such as `GET /props`. [llama.cpp server API](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md), [GGUF format](https://github.com/ggml-org/ggml/blob/master/docs/gguf.md) |
| PyTorch MPS | Optional, later. A process using the MPS backend cannot be identified from its name alone. Require an explicit opt-in adapter or user-supplied evidence, and do not infer loaded models from a Python process. |

Keep runtime-reported values, file-derived metadata, and estimates distinct. Estimate KV-cache size only when the required architecture, context length, precision, and concurrency inputs are known. Document the assumptions and omit the estimate when they are missing. Use finite network timeouts and response size limits, require loopback for the initial adapters, and reject redirects away from the configured endpoint. Never start inference, download models, or send prompts as part of inspection.

## Repository layout

Target layout. The current package already has `MetalTelemetry` and the `MetalTask` executable. Add the rest as milestones land.

```
MetalTask/
├── Package.swift
├── Sources/
│   ├── MetalTask/            App/, Views/, ViewModels/
│   ├── MetalTelemetry/       collector, device info, process monitor, memory monitor
│   └── ModelInspection/      Ollama, MLX, GGUF inspectors (separate module, no SwiftUI)
├── Tests/
├── LICENSE
└── README.md                 build steps, supported hardware, limits, Acknowledgments
```

## Release validation

- Run hardware-independent decoding, delta, and lifecycle tests with injected clocks and sanitized fixtures. Cover missing and malformed values, zero, invalid ranges, denial, counter rollback, disappearing clients, PID reuse, and unsupported machines.
- On at least two Apple Silicon generations, verify the declared minimum macOS and a current release where possible. Record exact chip, OS build, account privileges, available keys, and outcomes. Use a bounded Metal workload that allocates and touches a known buffer, sustains work, and exits. Record idle, steady load, and recovery. Compare activity trends with Activity Monitor's GPU History. Graphics footprint can differ from buffer size because of accounting and shared allocations.
- Run a 30-minute soak at the default cadence with rapid process churn, sleep/wake, and window reopen. Verify bounded memory and history, no overlapping reads, and no main-thread stalls or leftover workers. Aim for a device-poll p95 below 100 ms at 1 Hz on supported hardware, and record actual results before adjusting cadence.
- Test adapter failures with fixtures for missing fields, service down, timeout, malformed or oversized replies, unsupported model files, and ambiguous PID associations. Release only metrics whose provenance, scope, and units can be explained from validated evidence.
