import Foundation
import Metal

// Keep the same process alive before, during, and after a GPU-touched allocation.
guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }

func holdAllocation() {
    let bytes = 64 * 1_024 * 1_024
    guard let buffer = device.makeBuffer(length: bytes, options: .storageModePrivate),
          let command = queue.makeCommandBuffer(),
          let blit = command.makeBlitCommandEncoder() else { fatalError("Allocation failed") }
    blit.fill(buffer: buffer, range: 0..<bytes, value: 0xA5)
    blit.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    precondition(command.status == .completed)
    withExtendedLifetime(buffer) { Thread.sleep(forTimeInterval: 12) }
}

Thread.sleep(forTimeInterval: 8)
autoreleasepool { holdAllocation() }
Thread.sleep(forTimeInterval: 10)
