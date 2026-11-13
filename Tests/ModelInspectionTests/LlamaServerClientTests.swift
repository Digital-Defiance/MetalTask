import Foundation
import Testing
@testable import ModelInspection

@Test func readsLlamaServerMetadataWithoutRetainingPathsOrPrompts() throws {
    let data = Data("""
        {"model_path":"/private/models/fixture.gguf","total_slots":2,"is_sleeping":false,
         "default_generation_settings":{"n_ctx":4096,"prompt":"discard this"},
         "chat_template":"discard this too"}
        """.utf8)
    #expect(try LlamaServerClient.decode(data) == LlamaServerProperties(
        modelFilename: "fixture.gguf", contextLength: 4096, totalSlots: 2, isSleeping: false
    ))
}

@Test func recognizesSleepingLlamaServerWithNoModelDetails() throws {
    #expect(try LlamaServerClient.decode(Data(#"{"is_sleeping":true}"#.utf8)) == LlamaServerProperties(
        modelFilename: nil, contextLength: nil, totalSlots: nil, isSleeping: true
    ))
    #expect(throws: LocalModelRequestFailure.invalidResponse) {
        try LlamaServerClient.decode(Data(#"{"models":[]}"#.utf8))
    }
}
