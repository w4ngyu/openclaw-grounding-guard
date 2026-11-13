import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

@MainActor
extension DecisionViewModel {
    func applyImportedDocument(_ document: ImportedDecisionDocument) {
        let questions = document.questions.compactMap { item -> DecisionQuestion? in
            guard let kind = DecisionKind(rawValue: item.kind) else { return nil }
            return DecisionQuestion(
                kind: kind,
                instructions: item.instructions,
                options: item.options.map { DecisionOption(text: $0) }
            )
        }
        guard questions.count == document.questions.count else {
            status = "包含不支持的题型，未导入。"
            return
        }
        draft = DecisionDraft(state: document.state, questions: questions)
        answers = []
        rawResult = ""
        duration = nil
        status = "已导入 \(questions.count) 道题，检查内容后点击「执行决策」。"
    }

    func exportCurrentDocument() throws -> String {
        let document = ImportedDecisionDocument(
            state: draft.state,
            questions: draft.questions.map {
                ImportedDecisionQuestion(kind: $0.kind.rawValue,
                                         instructions: $0.instructions,
                                         options: $0.options.map(\.text))
            }
        )
        return try DecisionDocumentJSON.export(document)
    }

    func copyCurrentDocumentJSON() {
        do {
            let json = try exportCurrentDocument()
            #if os(iOS)
            UIPasteboard.general.string = json
            status = "当前背景和问题已复制为 JSON，可粘贴保存。"
            #else
            status = json
            #endif
        } catch {
            status = "无法导出：\(error.localizedDescription)"
        }
    }
}

struct DecisionDocumentImportView: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: (ImportedDecisionDocument) -> Void

    @State private var jsonText: String = ""
    @State private var errorText: String = ""
    @State private var showingPicker: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("导入题目 JSON").font(.title3.weight(.semibold))
                        Text("支持 JSON 文件或直接粘贴。导入后会转为可编辑的背景、选择题、是非题与等级评分。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button {
                            showingPicker = true
                        } label: {
                            Label("从文件导入", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)

                        #if os(iOS)
                        Button {
                            jsonText = UIPasteboard.general.string ?? ""
                            errorText = ""
                            if jsonText.isEmpty { errorText = "剪贴板没有文本，请先复制 JSON。" }
                        } label: {
                            Label("粘贴 JSON", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        #endif
                    }

                    Button {
                        jsonText = DecisionDocumentJSON.sample
                        errorText = ""
                    } label: {
                        Label("加载椭圆选择题示例", systemImage: "function")
                    }
                    .font(.subheadline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("JSON 内容").font(.headline)
                        TextEditor(text: $jsonText)
                            .font(.system(.footnote, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 260)
                            .padding(10)
                            .background(Color.gray.opacity(0.09),
                                        in: RoundedRectangle(cornerRadius: 12))
                        Text("必填：state、questions；问题 type 为 choice、noul 或 score。最多 8 道题，每题 2～8 个选项。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !errorText.isEmpty {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        validateAndImport()
                    } label: {
                        Label("校验并导入为可编辑题目", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("导入在本机完成；不会上传到网络。校验失败时保留输入，不覆盖当前题目。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("JSON 导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingPicker,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else {
                        throw DecisionDocumentImportError(message: "没有选择文件。")
                    }
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    let metadata = try url.resourceValues(forKeys: [.fileSizeKey])
                    if let size = metadata.fileSize, size > DecisionDocumentJSON.maxBytes {
                        throw DecisionDocumentImportError(message: "JSON 文件超过 128 KB。")
                    }
                    let data = try Data(contentsOf: url)
                    guard data.count <= DecisionDocumentJSON.maxBytes,
                          let text = String(data: data, encoding: .utf8) else {
                        throw DecisionDocumentImportError(message: "文件必须是 UTF-8 编码、128 KB 以下的 JSON。")
                    }
                    jsonText = text
                    errorText = ""
                } catch {
                    errorText = "读取文件失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func validateAndImport() {
        do {
            let document = try DecisionDocumentJSON.parse(jsonText)
            onImport(document)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
