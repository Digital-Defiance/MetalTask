# MetalTask

A native macOS GPU task manager in development for Apple Silicon. The SwiftUI window shows physical memory, default Metal device information, five minutes of device activity history, and a sortable list of observed GPU processes with graphics footprint where macOS permits the read. History starts fresh each time the window opens.

If you already use Ollama, open **Loaded Models** and select **Check Local Ollama** to see what the local service has loaded. Ollama is optional for MetalTask and its test suite.

Use **Loaded Models → GGUF file → Choose GGUF File** to inspect declared metadata in a local GGUF v2 or v3 file. Little-endian files are supported. For a split model, the inspector describes the selected shard and shows the declared shard count when available.

**Loaded Models → llama.cpp server** reads the configured model filename, context length, slot count, and sleep state from an existing local server.

**Loaded Models → LM Studio** reads loaded instances through LM Studio’s native v1 API. Start the local server from LM Studio’s Developer page if needed, enter its port (default `1234`), and select **Check LM Studio**. If authentication is enabled, enter the token in the optional secure field. For the default port without authentication, `metaltask --check-lm-studio` prints only the instance count.

## Install with Homebrew

Select Xcode with Swift 6, then run:

```sh
brew install digital-defiance/tap/metaltask
metaltask
```

The formula builds the app from source on Apple Silicon. You can also launch the installed app bundle with `open "$(brew --prefix metaltask)/libexec/MetalTask.app"`.

## Build and run

Use an Apple Silicon Mac and select an Xcode toolchain with Swift 6.

```sh
swift build
swift test
swift run MetalTask
```

Use `swift run MetalTask --sample-process-gpu` for a two-sample Terminal check of per-process GPU activity.
Use `swift run MetalTask --sample-graphics-footprint PID` to check a readable process. Graphics footprint is the dirty memory macOS charges to graphics categories and can include driver overhead or cached allocations.

Capture and compare local snapshots during the same boot session:

```sh
swift run MetalTask --snapshot-json > before.json
# Start or change the workload.
swift run MetalTask --snapshot-json > after.json
swift run MetalTask --compare before.json after.json
```

Snapshots contain process names, PIDs, and start times. Each capture probes graphics footprint for up to four rows, prioritizing observed GPU activity. To compare footprint for a known process, use `--snapshot-json --footprint-pid PID` on both captures.

You can also open `Package.swift` in Xcode and run the MetalTask scheme. The package targets macOS 14. [TODO.md](TODO.md) records the hardware and macOS versions actually tested.

## Development

- [SPEC.md](SPEC.md) defines telemetry semantics, architecture, validation, and release scope.
- [TODO.md](TODO.md) records verification, GPU workload commands, and next steps.

## Acknowledgments

Thanks to Scott Hanselman and the contributors to [gputaskman](https://github.com/shanselman/gputaskman) for the inspiration and macOS telemetry reference. [gpucap](https://github.com/Digital-Defiance/gpucap) is a development reference and test workload.

[MIT License](LICENSE)
