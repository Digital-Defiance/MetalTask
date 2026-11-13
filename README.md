# MetalTask

A native macOS GPU task manager in development for Apple Silicon. The current SwiftUI app shows physical memory and information about the default Metal device. Live GPU activity, process attribution, graphics footprint, and local model inspection are planned.

## Build and run

Use an Apple Silicon Mac and select an Xcode toolchain with Swift 6.

```sh
git clone https://github.com/Digital-Defiance/MetalTask.git
cd MetalTask
swift build
swift test
swift run MetalTask
```

The deployment target is macOS 14. See [TODO.md](TODO.md) for the verified environment and remaining compatibility checks. You can also open `Package.swift` in Xcode and run the MetalTask scheme. This bootstrap runs as a development executable. A signed app bundle is a later milestone.

## Development

- [SPEC.md](SPEC.md) defines telemetry semantics, architecture, validation, and release scope.
- [TODO.md](TODO.md) records verification and the next implementation steps.

Thanks to Scott Hanselman and the contributors to [gputaskman](https://github.com/shanselman/gputaskman) for the inspiration and macOS telemetry reference.

[MIT License](LICENSE)
