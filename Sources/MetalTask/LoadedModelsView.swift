import ModelInspection
import SwiftUI
import UniformTypeIdentifiers

struct LoadedModelsView: View {
    private enum Source {
        case ollama, gguf, llamaServer, lmStudio
    }

    private enum Status {
        case ready
        case checking
        case loaded([OllamaModel])
        case failed(String)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var status = Status.ready
    @State private var requestID: UUID?
    @State private var choosingFile = false
    @State private var selectedFile: URL?
    @State private var fileRequestID: UUID?
    @State private var fileResult: Result<GGUFMetadata, Error>?
    @State private var source = Source.ollama

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Model source", selection: $source) {
                Text("Local Ollama").tag(Source.ollama)
                Text("GGUF file").tag(Source.gguf)
                Text("llama.cpp server").tag(Source.llamaServer)
                Text("LM Studio").tag(Source.lmStudio)
            }
            .pickerStyle(.segmented)
            Group {
                switch source {
                case .ollama: content
                case .gguf: ggufContent
                case .llamaServer: LlamaServerView()
                case .lmStudio: LMStudioView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                if source == .gguf {
                    Button("Choose GGUF File…") { choosingFile = true }
                } else if source == .ollama {
                    Button("Check Local Ollama") {
                        status = .checking
                        requestID = UUID()
                    }
                    .disabled(isChecking)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 360)
        .task(id: requestID) {
            guard requestID != nil else { return }
            await checkModels()
        }
        .fileImporter(isPresented: $choosingFile,
                      allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data]) { result in
            switch result {
            case .success(let url):
                selectedFile = url
                fileResult = nil
                fileRequestID = UUID()
            case .failure(let error):
                selectedFile = nil
                fileResult = .failure(error)
                fileRequestID = nil
            }
        }
        .task(id: fileRequestID) {
            guard let selectedFile else { return }
            let result = await Self.inspectFile(selectedFile)
            guard !Task.isCancelled else { return }
            fileResult = result
        }
    }

    @ViewBuilder
    private var ggufContent: some View {
        switch fileResult {
        case .success(let metadata):
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(metadata.name ?? selectedFile?.lastPathComponent ?? "GGUF file").font(.headline)
                    if let architecture = metadata.architecture {
                        LabeledContent("Architecture", value: architecture)
                    }
                    if let fileType = metadata.fileType {
                        LabeledContent("GGUF file type", value: fileType.formatted(.number.grouping(.never)))
                    }
                    if let contextLength = metadata.contextLength {
                        LabeledContent("Declared context length", value: contextLength.formatted())
                    }
                    LabeledContent("Tensors in this file", value: metadata.tensorCount.formatted())
                    LabeledContent("GGUF version", value: metadata.version.formatted())
                    if let splitCount = metadata.splitCount, splitCount > 1 {
                        LabeledContent("Declared shard count", value: splitCount.formatted())
                    }
                }
            }
        case .failure(let error):
            if case GGUFInspector.Failure.unsupportedVersion = error {
                Text("This GGUF version or byte order is unsupported.")
            } else {
                Text("Couldn’t read GGUF metadata from this file.")
            }
        case nil:
            if selectedFile == nil {
                Text("Choose a GGUF file to see its declared model metadata.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Reading GGUF metadata…")
            }
        }
    }

    private nonisolated static func inspectFile(_ url: URL) async -> Result<GGUFMetadata, Error> {
        let read = Task.detached(priority: .utility) {
            Result {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return try GGUFInspector.inspect(url)
            }
        }
        return await withTaskCancellationHandler {
            await read.value
        } onCancel: {
            read.cancel()
        }
    }

    private var isChecking: Bool {
        if case .checking = status { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .ready:
            Text("Check for models already loaded by Ollama on this Mac.")
                .foregroundStyle(.secondary)
        case .checking:
            ProgressView("Checking local Ollama…")
        case .loaded(let models) where models.isEmpty:
            Text("Ollama is running with no models loaded.")
        case .loaded(let models):
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(models.indices, id: \.self) { index in
                        if index > 0 { Divider() }
                        modelDetails(models[index])
                    }
                }
            }
        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)
        }
    }

    private func modelDetails(_ model: OllamaModel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.name).font(.headline).textSelection(.enabled)
            if let quantization = model.quantization {
                LabeledContent("Quantization", value: quantization)
            }
            if let contextLength = model.contextLength {
                LabeledContent("Context length", value: contextLength.formatted())
            }
            if let bytes = model.gpuSizeBytes {
                LabeledContent("Ollama-reported GPU size", value: bytes.formatted(.byteCount(style: .memory)))
            }
            if let bytes = model.sizeBytes {
                LabeledContent("Ollama-reported total size", value: bytes.formatted(.byteCount(style: .memory)))
            }
            if let digest = model.digest, !digest.isEmpty {
                LabeledContent("Digest") {
                    Text(digest).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checkModels() async {
        do {
            let models = try await OllamaClient().loadedModels()
            try Task.checkCancellation()
            status = .loaded(models)
        } catch is CancellationError {
            return
        } catch let failure as OllamaClient.Failure {
            guard !Task.isCancelled else { return }
            switch failure {
            case .serviceUnavailable: status = .failed("Ollama isn’t reachable on this Mac.")
            case .timedOut: status = .failed("The local Ollama request timed out.")
            case .redirect: status = .failed("The local Ollama service returned a redirect.")
            case .httpStatus(let code): status = .failed("The local Ollama service returned HTTP \(code).")
            case .responseTooLarge: status = .failed("The local Ollama response exceeded the size limit.")
            case .invalidResponse: status = .failed("The local service returned an unsupported response.")
            }
        } catch {
            guard !Task.isCancelled else { return }
            status = .failed("Couldn’t read the local Ollama model list.")
        }
    }
}
