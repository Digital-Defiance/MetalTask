import Foundation
import Testing
@testable import ModelInspection

@Test(arguments: [UInt32(2), 3])
func readsGGUFMetadataAndSkipsTokenizerArrays(_ version: UInt32) throws {
    var file = header(version: version, tensors: 1, entries: 6)
    file += string("general.name") + number(UInt32(8)) + string("Fixture Model")
    file += string("tokenizer.ggml.tokens") + number(UInt32(9)) + number(UInt32(8))
    file += number(UInt64(2)) + string("alpha") + string("beta")
    file += string("general.architecture") + number(UInt32(8)) + string("llama")
    file += string("llama.context_length") + number(UInt32(4)) + number(UInt32(4096))
    file += string("general.file_type") + number(UInt32(4)) + number(UInt32(15))
    file += string("split.count") + number(UInt32(2)) + number(UInt16(2))
    file += tensor(offset: 0)
    file.append(contentsOf: repeatElement(0, count: (32 - file.count % 32) % 32 + 4))

    try withFile(file) {
        let metadata = try GGUFInspector.inspect($0)
        #expect(metadata == GGUFMetadata(
            version: version, name: "Fixture Model", architecture: "llama", fileType: 15,
            contextLength: 4096, tensorCount: 1, splitCount: 2
        ))
    }
}

@Test func rejectsUnsupportedTruncatedAndOversizedGGUF() throws {
    try withFile(header(version: 1)) { url in
        #expect(throws: GGUFInspector.Failure.unsupportedVersion(1)) { try GGUFInspector.inspect(url) }
    }
    try withFile(header(entries: 1)) { url in
        #expect(throws: GGUFInspector.Failure.truncated) { try GGUFInspector.inspect(url) }
    }
    try withFile(header(entries: 1) + number(UInt64.max)) { url in
        #expect(throws: GGUFInspector.Failure.limitExceeded) { try GGUFInspector.inspect(url) }
    }
    let array = string("tokens") + number(UInt32(9)) + number(UInt32(8)) + number(UInt64.max)
    try withFile(header(entries: 1) + array) { url in
        #expect(throws: GGUFInspector.Failure.limitExceeded) { try GGUFInspector.inspect(url) }
    }
}

@Test func rejectsOverflowingAndOutOfFileTensorOffsets() throws {
    try withFile(header(tensors: 1) + tensor(offset: UInt64.max - 31)) { url in
        #expect(throws: GGUFInspector.Failure.invalidHeader) { try GGUFInspector.inspect(url) }
    }
    try withFile(header(tensors: 1) + tensor(offset: 128)) { url in
        #expect(throws: GGUFInspector.Failure.truncated) { try GGUFInspector.inspect(url) }
    }
}

private func header(version: UInt32 = 3, tensors: UInt64 = 0, entries: UInt64 = 0) -> Data {
    Data("GGUF".utf8) + number(version) + number(tensors) + number(entries)
}

private func tensor(offset: UInt64) -> Data {
    string("tensor") + number(UInt32(1)) + number(UInt64(1)) + number(UInt32(0)) + number(offset)
}

private func string(_ value: String) -> Data {
    number(UInt64(value.utf8.count)) + Data(value.utf8)
}

private func number<T: FixedWidthInteger>(_ value: T) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

private func withFile(_ data: Data, check: (URL) throws -> Void) throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try data.write(to: file)
    try check(file)
}
