import ModelInspection
import SwiftUI

struct LlamaServerView: View {
    @State private var port = "8080"
    @State private var request: UInt16?
    @State private var properties: LlamaServerProperties?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Local port", text: $port).frame(width: 130)
                Button("Check Local Server") {
                    properties = nil
                    message = nil
                    request = parsedPort
                }
                .disabled(parsedPort == nil || request != nil)
            }
            if let properties {
                if let filename = properties.modelFilename {
                    LabeledContent("Configured model file", value: filename)
                }
                if let length = properties.contextLength {
                    LabeledContent("Server-reported context length", value: length.formatted())
                }
                if let slots = properties.totalSlots {
                    LabeledContent("Total slots", value: slots.formatted())
                }
                if let sleeping = properties.isSleeping {
                    LabeledContent("Server state", value: sleeping ? "Sleeping" : "Awake")
                }
            } else if request != nil {
                ProgressView("Checking local llama.cpp…")
            } else {
                Text(message ?? "Check a llama.cpp server already running on this Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: request) {
            guard let request else { return }
            do {
                let response = try await LlamaServerClient(port: request).properties()
                try Task.checkCancellation()
                properties = response
            } catch is CancellationError {
                return
            } catch let error as LocalModelRequestFailure {
                guard !Task.isCancelled else { return }
                switch error {
                case .serviceUnavailable: message = "llama.cpp isn’t reachable on this port."
                case .timedOut: message = "The local server request timed out."
                case .redirect: message = "The local server returned a redirect."
                case .httpStatus(let code): message = "The local server returned HTTP \(code)."
                case .responseTooLarge: message = "The local server response exceeded the size limit."
                case .invalidResponse: message = "The local server returned unsupported properties."
                }
            } catch {
                guard !Task.isCancelled else { return }
                message = "Couldn’t read the local server properties."
            }
            self.request = nil
        }
    }

    private var parsedPort: UInt16? {
        guard let value = UInt16(port), value > 0 else { return nil }
        return value
    }
}
