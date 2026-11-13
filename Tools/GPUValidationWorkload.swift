import Metal

// A standard-user validation workload with a fixed allocation and at most one
// submitted command buffer at a time. The last command drains before exit.
let shader = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void exercise(device float *values [[buffer(0)]],
                         uint index [[thread_position_in_grid]]) {
        float value = values[index] + float(index % 997) * 0.001;
        for (uint i = 0; i < 256; ++i) {
            value = sin(value) * cos(value * 1.31) + sqrt(abs(value) + 1.0);
        }
        values[index] = value;
    }
    """

let count = 1 << 20
let byteCount = count * MemoryLayout<Float>.stride
guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue(),
      let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
    fatalError("Metal device, queue or 4 MiB buffer unavailable")
}
let library = try device.makeLibrary(source: shader, options: nil)
guard let kernel = library.makeFunction(name: "exercise") else {
    fatalError("Validation kernel unavailable")
}
let pipeline = try device.makeComputePipelineState(function: kernel)
buffer.contents().bindMemory(to: Float.self, capacity: count)
    .initialize(repeating: 0, count: count)

let clock = ContinuousClock()
let started = clock.now
let deadline = started + .seconds(12)
var completed = 0
var gpuSeconds = 0.0
while clock.now < deadline {
    try autoreleasepool {
        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            fatalError("Could not encode validation workload")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: pipeline.threadExecutionWidth, height: 1, depth: 1)
        )
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        gpuSeconds += command.gpuEndTime - command.gpuStartTime
        completed += 1
    }
}
print("Completed \(completed) GPU commands with a \(byteCount)-byte buffer")
let elapsed = started.duration(to: clock.now).components
let wallSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
print("Mean command-buffer GPU ms/s: \(gpuSeconds * 1_000 / wallSeconds)")
