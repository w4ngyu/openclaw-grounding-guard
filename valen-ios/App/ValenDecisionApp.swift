import SwiftUI
import PhotosUI
import CryptoKit
import UIKit

private enum ValenSettings {
    static let serverURL = URL(string: "http://127.0.0.1:43227")!
    static let revision = "8104bad0c9b8"
    static let modelRepository = "Valen-Team/Valen-Decision-1.5-4B-GGUF"
    static let modelFile = "Valen-Decision-1.5-4B-Q8_0.gguf"
    static let visionFile = "vision-native-limits-F32.gguf"
    static let modelSHA256 = "0b9a789f9477cbd1a11150f0b6d584743e44165a2ab7c4ec44c4107f1640e05f"
    static let visionSHA256 = "0334f15885a1a9463eca9577312f411eac48c970250ce0b7e42aed20a6006b85"
}

private func sha256OfFile(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
        let bytes = try handle.read(upToCount: 1024 * 1024) ?? Data()
        if bytes.isEmpty { break }
        hasher.update(data: bytes)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private enum ValenDecisionType: String, CaseIterable, Identifiable {
    case choice = "Choice"
    case noul = "Noul"
    case score = "Score"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .choice: return "多选决策"
        case .noul: return "是否判断"
        case .score: return "等级评分"
        }
    }
}

@MainActor
private final class ValenStore: ObservableObject {
    @Published var status = "请先下载 4B 模型和视觉权重（首次需要网络）。"
    @Published var output = ""
    @Published var busy = false
    @Published var ready = false
    @Published var text = "用户表示已经被重复扣费两次，要求今天退款，否则将取消服务。"
    @Published var question = "应当如何处理这条请求？"
    @Published var alternatives = "优先退款并转人工处理\n普通客服排队\n无需处理"
    @Published var type: ValenDecisionType = .choice
    @Published var pictureData: [Data] = []

    private var modelDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("ValenDecision4B", isDirectory: true)
    }
    private var modelURL: URL { modelDirectory.appendingPathComponent(ValenSettings.modelFile) }
    private var visionURL: URL { modelDirectory.appendingPathComponent(ValenSettings.visionFile) }

    var filesReady: Bool {
        FileManager.default.fileExists(atPath: modelURL.path) &&
        FileManager.default.fileExists(atPath: visionURL.path)
    }

    func refreshStatus() {
        if filesReady && !ready && !busy { status = "模型文件存在，可以启动离线推理引擎。" }
    }

    private func downloadFile(_ name: String, expectedSHA256: String) async throws {
        let destination = modelDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            let actual = try await Task.detached(priority: .utility) {
                try sha256OfFile(destination)
            }.value
            if actual == expectedSHA256 { return }
            try FileManager.default.removeItem(at: destination)
        }

        let url = URL(string: "https://huggingface.co/\(ValenSettings.modelRepository)/resolve/\(ValenSettings.revision)/\(name)?download=true")!
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "ValenDownload", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "下载服务器未返回成功状态"
            ])
        }
        let actual = try await Task.detached(priority: .utility) {
            try sha256OfFile(temporary)
        }.value
        guard actual == expectedSHA256 else {
            throw NSError(domain: "ValenDownload", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "\(name) 校验失败；文件可能不完整。"
            ])
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    func downloadModels() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var directory = modelDirectory
            try directory.setResourceValues(values)

            status = "下载并校验 4B Q8_0 模型（约 4.20 GiB）…"
            try await downloadFile(ValenSettings.modelFile, expectedSHA256: ValenSettings.modelSHA256)
            status = "下载并校验视觉模型（约 1.24 GiB）…"
            try await downloadFile(ValenSettings.visionFile, expectedSHA256: ValenSettings.visionSHA256)
            status = "下载完成，SHA-256 校验通过。现在可以启动离线推理。"
        } catch {
            status = "下载失败：\(error.localizedDescription)"
        }
    }

    func startServer() async {
        guard !busy else { return }
        guard filesReady else {
            status = "请先下载两个模型文件。"
            return
        }
        busy = true
        ready = false
        defer { busy = false }

        let code = modelURL.path.withCString { modelPtr in
            visionURL.path.withCString { visionPtr in
                valen_start_server(modelPtr, visionPtr, true)
            }
        }
        if code != 0 {
            status = "引擎启动失败，返回码 \(code)"
            return
        }
        status = "正在加载 Valen 4B 到内存，首次加载可能较慢…"
        for _ in 0..<180 {
            do {
                let request = URLRequest(url: ValenSettings.serverURL.appendingPathComponent("health"))
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    ready = true
                    status = "离线引擎已就绪，可执行中文及图片决策。"
                    _ = data
                    return
                }
            } catch { }
            if valen_server_is_running() == 0 {
                status = "引擎退出，返回码 \(valen_server_last_exit_code())；请检查设备内存。"
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        status = "引擎尚未就绪；可能在加载或内存不足。"
    }

    func importImages(_ selection: [PhotosPickerItem]) async {
        var result: [Data] = []
        for item in selection.prefix(3) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                let limit: CGFloat = 1024
                let factor = min(1, limit / max(image.size.width, image.size.height))
                let newSize = CGSize(width: max(1, image.size.width * factor),
                                     height: max(1, image.size.height * factor))
                let prepared = UIGraphicsImageRenderer(size: newSize).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
                if let jpeg = prepared.jpegData(compressionQuality: 0.80) {
                    result.append(jpeg)
                }
            } catch {
                status = "读取图片失败：\(error.localizedDescription)"
            }
        }
        pictureData = result
    }

    func decide() async {
        guard ready, !busy else { return }
        busy = true
        defer { busy = false }
        status = "正在 iPhone 本地执行决策…"
        do {
            var parts: [[String: Any]] = [
                ["type": "text", "text": text]
            ]
            for image in pictureData {
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString()]
                ])
            }

            var definition: [String: Any] = [
                "type": type.rawValue.lowercased(),
                "instructions": question
            ]
            let options = alternatives
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            switch type {
            case .choice:
                guard options.count >= 2 else { status = "至少输入两个选项。"; return }
                var criteria: [String: String] = [:]
                for (index, item) in options.enumerated() {
                    criteria["option_\(index + 1)"] = item
                }
                definition["criteria"] = criteria
            case .score:
                guard options.count >= 2 else { status = "至少输入两个有序评分等级。"; return }
                definition["criteria"] = options
            case .noul:
                break
            }

            let payload: [String: Any] = [
                "state": ["messages": [["role": "user", "content": parts]]],
                "questions": ["decision": definition]
            ]
            let json = try JSONSerialization.data(withJSONObject: payload)
            var request = URLRequest(url: ValenSettings.serverURL.appendingPathComponent("v1/systemone"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = json
            request.timeoutInterval = 180
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "Valen", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "本地引擎没有响应"])
            }
            if let object = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                        options: [.prettyPrinted, .sortedKeys]),
               let string = String(data: pretty, encoding: .utf8) {
                output = string
            } else {
                output = String(data: data, encoding: .utf8) ?? "<invalid response>"
            }
            status = http.statusCode == 200 ? "已完成本地推理。" : "本地引擎返回 HTTP \(http.statusCode)"
        } catch {
            status = "推理失败：\(error.localizedDescription)"
        }
    }
}

@main
struct ValenDecisionApp: App {
    var body: some Scene {
        WindowGroup {
            ValenContentView()
        }
    }
}

private struct ValenContentView: View {
    @StateObject private var model = ValenStore()
    @State private var selectedPhotos: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("运行状态") {
                    Text(model.status).font(.subheadline).textSelection(.enabled)
                    HStack {
                        Button("下载 4B 模型") { Task { await model.downloadModels() } }
                            .disabled(model.busy)
                        Spacer()
                        Button("启动离线引擎") { Task { await model.startServer() } }
                            .disabled(model.busy || !model.filesReady || model.ready)
                    }
                    .buttonStyle(.bordered)
                    Text("模型和视觉权重约占 5.5 GiB，首次下载需要更多临时空间。下载后所有决策均请求手机内部 127.0.0.1。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("决策输入") {
                    TextEditor(text: $model.text).frame(minHeight: 110)
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 3, matching: .images) {
                        Label("选择图片（最多 3 张）", systemImage: "photo.on.rectangle")
                    }
                    Text("已导入 \(model.pictureData.count) 张图片").font(.caption).foregroundStyle(.secondary)
                    Picker("类型", selection: $model.type) {
                        ForEach(ValenDecisionType.allCases) { kind in
                            Text(kind.name).tag(kind)
                        }
                    }
                    TextField("决策问题", text: $model.question, axis: .vertical)
                    if model.type != .noul {
                        Text("每行一个选项或等级，从上到下保持顺序：").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $model.alternatives).frame(minHeight: 85)
                    }
                    Button("执行原生决策") { Task { await model.decide() } }
                        .disabled(!model.ready || model.busy)
                        .buttonStyle(.borderedProminent)
                }
                Section("模型返回的原始概率与结果") {
                    ScrollView(.horizontal) {
                        Text(model.output.isEmpty ? "暂无结果" : model.output)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Valen Decision 4B")
            .onAppear { model.refreshStatus() }
            .onChange(of: selectedPhotos) { _, items in
                Task { await model.importImages(items) }
            }
        }
    }
}
