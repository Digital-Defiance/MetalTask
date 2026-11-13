# MetalTask specification

## Product and scope

MetalTask is an MIT-licensed macOS GPU task manager for Apple Silicon. It answers three questions in order.

1. Is the GPU busy?
2. Which visible processes are submitting GPU work, and how much graphics memory does macOS attribute to them?
3. For a recognized local inference runtime, which models are loaded and what can it report about their memory?

Build a native Swift 6 application using SwiftUI, Swift Charts, and Swift concurrency. Use macOS 14 as the initial deployment target. Treat it as a build target until the hardware and OS matrix is verified. The first usable release has a live device summary, a process table, and explicit status for each metric. Process control, exact per-engine attribution, and Intel or external GPU support are outside the first release. Model inspection and the menu-bar view follow the monitoring baseline.

The project draws inspiration from Scott Hanselman and the [gputaskman contributors](https://github.com/shanselman/gputaskman#macos-apple-silicon). Use their macOS notes as a comparison source. MetalTask is independently implemented with no Python runtime dependency. Preserve applicable notices if upstream code is adapted in the future.

## Telemetry sources

| Metric | Source and availability | Display contract |
| --- | --- | --- |
| Default GPU name, unified-memory flag, recommended working set | Public Metal device properties | Available in the bootstrap. The working set is a performance recommendation, with no implication about currently free memory. [Apple Metal documentation](https://developer.apple.com/documentation/metal/mtldevice/recommendedmaxworkingsetsize) |
| Installed physical memory | `ProcessInfo.physicalMemory` | Label as system physical memory. It is shared by CPU and GPU on Apple Silicon. |
| Device utilization | Candidate `IOAccelerator` registry service, `PerformanceStatistics` → `Device Utilization %` | Label as device-wide GPU activity. Accept a numeric value in 0–100 only after verifying the field's scale. Preserve an observed zero. |
| Device GPU allocations | Candidate `Alloc system memory` in the same dictionary | Label as driver-reported GPU allocations once byte units and semantics are verified. Keep any `In use system memory` observation separate until its meaning is established. |
| Per-process GPU activity | Candidate `AGXDeviceUserClient` entries with creator PID and cumulative GPU time | Derive an activity rate from matched client deltas only after verifying time units and ownership. Show coverage limits and gaps. |
| Process names and lifetimes | SDK-declared `libproc` calls for PID and start time, with `NSWorkspace` for app names and icons | Include background processes when visible. Represent exited or inaccessible PIDs without misattributing metrics. |
| Process graphics footprint | Optional `/usr/bin/footprint` probe for OS graphics categories | A slower, permission-dependent OS accounting value. RSS and general process footprint may be shown separately with their own labels. |

IOKit provides documented registry reads. Service classes, driver dictionaries, individual keys, units, and access rules are implementation details that can vary with chip and OS. Isolate them in replaceable providers and check types, ranges, and units before conversion. Use the documented device registry identifier where a reliable match can be established. If several candidate accelerators are visible and mapping is ambiguous, withhold the metric. Metal's `currentAllocatedSize` is useful for a test workload's own resources. Its API does not promise whole-system or cross-process accounting. [Apple IOKit registry reads](https://developer.apple.com/documentation/iokit/1514310-ioregistryentrycreatecfpropertie), [Apple Metal allocation counter](https://developer.apple.com/documentation/metal/mtldevice/currentallocatedsize), [gputaskman macOS observations](https://github.com/shanselman/gputaskman#macos-apple-silicon)

Physical memory, Metal's working-set recommendation, driver allocation accounting, graphics footprint, and runtime-reported memory describe different scopes. Keep these as separate byte metrics. Shared pages, allocations versus residency, and incomplete visibility prevent a reliable reconciliation by summing process rows. Use consistent byte formatting with units and never label the shared pool as dedicated VRAM.

## Collection and data model

`MetalTelemetry` owns typed values, native source adapters, decoding, and sampling. It has no SwiftUI dependency. The bootstrap exposes `SystemSnapshot.capture()` for startup metadata. Add a separate periodic sample for device metrics, then extend it to process metrics after the device provider is proven. Keep future runtime adapters independent from both the SwiftUI app and OS collection.

- Each periodic snapshot carries an observation time and per-metric source and scope. Store bytes as `UInt64`. Represent utilization as percent in a dedicated field.
- Track quality (measured, derived, estimated) separately from availability (fresh, stale, unavailable). Give unavailable readings a reason such as warming up, access denied, unsupported schema, ambiguous device, or source error. A stale reading carries its last observation time and can never become a fresh zero.
- Keep client baselines keyed by registry entry identity and process identity (PID plus start time). Normalize only validated deltas by actual monotonic elapsed time. Reset affected baselines on client turnover, PID reuse, counter rollback, sleep/wake, or excessive gaps. A disappearing client must not subtract from surviving clients' deltas. Mark partial coverage when appropriate. If overlap makes summed client rates unsuitable as a percentage, use GPU-time rate with explicit units. Process rates need not add up to the device reading.
- Use an actor for polling state and serialize each source's reads. Start with one device sample per second and bound the history to five minutes. Skip missed ticks rather than queueing reads. Put slow or blocking OS probes on a bounded worker queue off the main actor and publish immutable, sendable snapshots to the main-actor view model. Cancel polling when the last consumer disappears.
- Run graphics-footprint probes on demand or on a separate slower schedule. If subprocess probing proves viable, use a fixed executable with validated PID arguments, bounded output and concurrency, timeout, and cancellation. Recheck process identity before attaching the result. Treat exit, denial, unsupported output, and timeout separately.

## Interface and permissions

The main window opens with device activity history and labeled memory metrics above a sortable, searchable process table. Sort unknown values after observed values in either direction. Display process name, PID, GPU activity, graphics footprint, and source or availability in row details. Leave gaps for unavailable chart points. The detail panel later shows model metadata and confidence of attribution. Expose readable status text, keyboard navigation, and accessible chart summaries. A menu-bar view can reuse the same collector once sampling overhead and lifecycle are verified.

Baseline monitoring runs as a standard user with no privileged helper, blanket disk access, or task-port access. Treat a denied graphics or process probe as a row-level limitation. Validate own-process, same-user, cross-user, and protected process behavior independently. An unsandboxed build still encounters macOS protections. Avoid scanning other apps' private containers, process environments, and unrelated files. Keep diagnostic fixtures sanitized and omit paths, account names, and prompts from normal logs.

The distribution milestone creates a signed macOS app bundle for direct Developer ID distribution with hardened runtime and notarization. The development SwiftPM executable is the initial entry point. Evaluate Mac App Store sandbox compatibility separately before making distribution commitments. [Apple distribution comparison](https://developer.apple.com/macos/distribution), [Apple notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Model inspection roadmap

| Stage | Evidence and limits |
| --- | --- |
| Ollama | Offer explicit opt-in to the local service and query `GET /api/ps`. Display model, digest, quantization, context length, and sizes when present. Label `size_vram` as runtime-reported GPU size. Attach models to the service unless independent evidence links a runner PID. [Ollama API](https://docs.ollama.com/api/ps) |
| MLX | Support a user-selected MLX model directory or an opt-in adapter for a known runtime such as MLX LM. Read bounded config and shard metadata for architecture and quantization. A directory or process name alone cannot establish that the weights are loaded. [MLX LM](https://github.com/ml-explore/mlx-lm) |
| llama.cpp and GGUF | Use a user-selected GGUF file or a supported, explicitly configured loopback server. Validate which metadata its version exposes through read-only endpoints such as `GET /props`. Parse bounded GGUF metadata with version, length, offset, and integer-overflow checks. A file's size or quantization does not establish GPU placement. [llama.cpp server API](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md), [GGUF format](https://github.com/ggml-org/ggml/blob/master/docs/gguf.md) |

Keep runtime-reported values, file-derived metadata, and estimates distinct. Estimate KV-cache size only when the required architecture, context length, precision, and concurrency inputs are known. Document the assumptions and omit the estimate when they are missing. Use finite network timeouts and response size limits, require loopback for the initial adapters, and reject redirects away from the configured endpoint. Never start inference, download models, or send prompts as part of inspection.

## Release validation

- Run hardware-independent decoding, delta, and lifecycle tests with injected clocks and sanitized fixtures. Cover missing and malformed values, zero, invalid ranges, denial, counter rollback, disappearing clients, PID reuse, and unsupported machines.
- On at least two Apple Silicon generations, verify the declared minimum macOS and a current release where possible. Record exact chip, OS build, account privileges, available keys, and outcomes. Use a bounded Metal workload that allocates and touches a known buffer, sustains work, and exits. Record idle, steady load, and recovery. Compare activity trends with Activity Monitor's GPU History. Graphics footprint can differ from buffer size because of accounting and shared allocations.
- Run a 30-minute soak at the default cadence with rapid process churn, sleep/wake, and window reopen. Verify bounded memory and history, no overlapping reads, and no main-thread stalls or leftover workers. Aim for a device-poll p95 below 100 ms at 1 Hz on supported hardware, and record actual results before adjusting cadence.
- Test adapter failures with fixtures for missing fields, service down, timeout, malformed or oversized replies, unsupported model files, and ambiguous PID associations. Release only metrics whose provenance, scope, and units can be explained from validated evidence.
