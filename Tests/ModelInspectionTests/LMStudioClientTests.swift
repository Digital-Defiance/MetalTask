import Foundation
import Testing
@testable import ModelInspection

@Test func listsOnlyLoadedLMStudioInstances() throws {
    let response = Data("""
    {"models":[
      {"key":"downloaded","loaded_instances":[]},
      {"key":"family/model","display_name":"Fixture","architecture":"llama","quantization":{"name":"Q4"},
       "loaded_instances":[{"id":"one","config":{"context_length":4096,"offload_kv_cache_to_gpu":false}},
                           {"id":"two"}]}
    ]}
    """.utf8)
    let loaded = try LMStudioClient.decode(response)
    #expect(loaded.map(\.id) == ["one", "two"])
    #expect(loaded.first?.modelName == "Fixture")
    #expect(loaded.first?.contextLength == 4096)
    #expect(loaded.first?.kvCacheOnGPU == false)
    #expect(loaded.last?.contextLength == nil)
    #expect(throws: LocalModelRequestFailure.invalidResponse) {
        try LMStudioClient.decode(Data(#"{"models":[{"key":"missing-state"}]}"#.utf8))
    }
}
