import ModelInspection
import SwiftUI

struct LMStudioView: View {
    @State private var port = "1234"
    @State private var token = ""
    @State private var requestID: UUID?
    @State private var instances: [LMStudioInstance]?
    @State private var status = "Start the local server from LM Studio’s Developer page."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Local port", text: $port).frame(width: 100)
                SecureField("API token (optional)", text: $token)
                Button("Check LM Studio") { requestID = UUID() }
                    .disabled(parsedPort == nil || requestID != nil)
            }
            .disabled(requestID != nil)
            if requestID != nil {
                ProgressView("Checking LM Studio…")
            } else if let instances, !instances.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(instances.indices, id: \.self) { index in
                            let instance = instances[index]
                            if index > 0 { Divider() }
                            Text(instance.modelName).font(.headline)
                            LabeledContent("Loaded instance", value: instance.id)
                            if let value = instance.architecture { LabeledContent("Architecture", value: value) }
                            if let value = instance.quantization { LabeledContent("Quantization", value: value) }
                            if let value = instance.contextLength {
                                LabeledContent("Configured context length", value: value.formatted())
                            }
                            if let value = instance.kvCacheOnGPU {
                                LabeledContent("KV cache GPU offload", value: value ? "Enabled" : "Disabled")
                            }
                        }
                    }
                }
            } else {
                Text(status).foregroundStyle(.secondary)
            }
        }
        .task(id: requestID) {
            guard requestID != nil, let parsedPort else { return }
            instances = nil
            defer { if !Task.isCancelled { requestID = nil } }
            do {
                let result = try await LMStudioClient(port: parsedPort, token: token).loadedInstances()
                try Task.checkCancellation()
                instances = result
                status = "LM Studio reports no loaded models."
            } catch {
                guard !Task.isCancelled else { return }
                switch error {
                case LocalModelRequestFailure.httpStatus(401), LocalModelRequestFailure.httpStatus(403):
                    status = "LM Studio requires a valid API token."
                case LocalModelRequestFailure.serviceUnavailable:
                    status = "LM Studio isn’t reachable on this port."
                default:
                    status = "Couldn’t read loaded instances. Check that LM Studio’s native v1 API is available."
                }
            }
        }
    }

    private var parsedPort: UInt16? {
        guard let value = UInt16(port), value > 0 else { return nil }
        return value
    }
}
