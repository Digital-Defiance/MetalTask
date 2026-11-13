import Darwin
import Foundation

public struct GGUFMetadata: Equatable, Sendable {
    public let version: UInt32
    public let name: String?
    public let architecture: String?
    public let fileType: UInt32?
    public let contextLength: UInt32?
    public let tensorCount: UInt64
    public let splitCount: UInt16?
}

public enum GGUFInspector {
    public enum Failure: Error, Equatable {
        case invalidHeader
        case unsupportedVersion(UInt32)
        case truncated
        case limitExceeded
    }

    public static func inspect(_ url: URL) throws -> GGUFMetadata {
        guard url.isFileURL else { throw Failure.invalidHeader }
        let fd = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) } ?? -1
        }
        guard fd >= 0 else { throw CocoaError(.fileReadUnknown) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else {
            throw Failure.invalidHeader
        }
        var reader = Reader(handle: handle, size: UInt64(info.st_size))
        return try reader.inspect()
    }

    private struct Reader {
        let handle: FileHandle
        let size: UInt64
        var offset: UInt64 = 0
        var remainingArrayItems: UInt64 = 2_000_000

        mutating func inspect() throws -> GGUFMetadata {
            guard try read(4) == Data("GGUF".utf8) else { throw Failure.invalidHeader }
            let version = try integer(UInt32.self)
            guard version == 2 || version == 3 else { throw Failure.unsupportedVersion(version) }
            let tensorCount = try integer(UInt64.self)
            let entryCount = try integer(UInt64.self)
            guard tensorCount <= 100_000, entryCount <= 16_384 else { throw Failure.limitExceeded }
            var strings: [String: String] = [:]
            var numbers: [String: UInt32] = [:]
            var splitCount: UInt16?
            var keys: Set<String> = []

            for _ in 0..<entryCount {
                try Task.checkCancellation()
                let key = try string(max: 1024)
                guard !key.isEmpty, keys.insert(key).inserted else { throw Failure.invalidHeader }
                let type = try integer(UInt32.self)
                switch (key, type) {
                case ("general.name", 8), ("general.architecture", 8):
                    strings[key] = try string(max: 4096)
                case (_, 4) where key == "general.file_type" || key == "general.alignment"
                    || key.hasSuffix(".context_length"):
                    numbers[key] = try integer(UInt32.self)
                case ("split.count", 2):
                    splitCount = try integer(UInt16.self)
                default:
                    try skipValue(type)
                }
            }

            let alignment = UInt64(numbers["general.alignment"] ?? 32)
            guard alignment >= 8, alignment <= 1_048_576, alignment.isMultiple(of: 8),
                  alignment.nonzeroBitCount == 1 else { throw Failure.invalidHeader }
            var largestOffset: UInt64 = 0
            for _ in 0..<tensorCount {
                try Task.checkCancellation()
                let nameLength = try integer(UInt64.self)
                guard (1...64).contains(nameLength) else { throw Failure.invalidHeader }
                try skip(nameLength)
                let dimensions = try integer(UInt32.self)
                guard (1...4).contains(dimensions) else { throw Failure.invalidHeader }
                var elements: UInt64 = 1
                for _ in 0..<dimensions {
                    let dimension = try integer(UInt64.self)
                    let (product, overflow) = elements.multipliedReportingOverflow(by: dimension)
                    guard dimension > 0, !overflow, product <= Int64.max else { throw Failure.invalidHeader }
                    elements = product
                }
                try skip(4) // Tensor type. Metadata inspection never decodes tensor contents.
                let relative = try integer(UInt64.self)
                guard relative.isMultiple(of: alignment) else { throw Failure.invalidHeader }
                largestOffset = max(largestOffset, relative)
            }
            if tensorCount > 0 {
                let payloadStart = (offset + alignment - 1) & ~(alignment - 1)
                let (lastTensor, overflow) = payloadStart.addingReportingOverflow(largestOffset)
                guard !overflow else { throw Failure.invalidHeader }
                guard lastTensor < size else { throw Failure.truncated }
            }
            let architecture = strings["general.architecture"]
            return GGUFMetadata(
                version: version, name: strings["general.name"], architecture: architecture,
                fileType: numbers["general.file_type"],
                contextLength: architecture.flatMap { numbers["\($0).context_length"] },
                tensorCount: tensorCount, splitCount: splitCount
            )
        }

        mutating func skipValue(_ type: UInt32) throws {
            if type == 8 {
                let length = try integer(UInt64.self)
                try skip(length)
            } else if type == 9 {
                let itemType = try integer(UInt32.self)
                let count = try integer(UInt64.self)
                guard count <= remainingArrayItems else { throw Failure.limitExceeded }
                remainingArrayItems -= count
                if itemType == 8 {
                    for _ in 0..<count {
                        try Task.checkCancellation()
                        let length = try integer(UInt64.self)
                        try skip(length)
                    }
                } else {
                    try skip(count * Self.scalarSize(itemType))
                }
            } else {
                try skip(Self.scalarSize(type))
            }
        }

        static func scalarSize(_ type: UInt32) throws -> UInt64 {
            switch type {
            case 0, 1, 7: 1
            case 2, 3: 2
            case 4, 5, 6: 4
            case 10, 11, 12: 8
            default: throw Failure.invalidHeader
            }
        }

        mutating func string(max: UInt64) throws -> String {
            let count = try integer(UInt64.self)
            guard count <= max else { throw Failure.limitExceeded }
            guard let value = String(data: try read(count), encoding: .utf8) else {
                throw Failure.invalidHeader
            }
            return value
        }

        mutating func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            try read(UInt64(MemoryLayout<T>.size)).withUnsafeBytes {
                T(littleEndian: $0.loadUnaligned(as: T.self))
            }
        }

        mutating func read(_ count: UInt64) throws -> Data {
            try advance(count)
            guard count > 0 else { return Data() }
            guard let data = try handle.read(upToCount: Int(count)), data.count == count else {
                throw Failure.truncated
            }
            return data
        }

        mutating func skip(_ count: UInt64) throws {
            try advance(count)
            try handle.seek(toOffset: offset)
        }

        mutating func advance(_ count: UInt64) throws {
            let (end, overflow) = offset.addingReportingOverflow(count)
            guard !overflow, end <= 32 * 1024 * 1024 else { throw Failure.limitExceeded }
            guard end <= size else { throw Failure.truncated }
            offset = end
        }
    }
}
