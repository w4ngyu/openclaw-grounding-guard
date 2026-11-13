import Foundation
import SwiftUI
import LayaKit
#if os(iOS)
import UIKit
#endif

@main
struct LayaDemoApp: App {
    var body: some Scene {
        WindowGroup {
            DecisionHomeView()
        }
    }
}

enum ModelLocator {
    static func find() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Model"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("rl_agent_config.json").path) {
            return bundled
        }
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let candidate = docs.appendingPathComponent("Model")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("rl_agent_config.json").path) {
                return candidate
            }
        }
        return nil
    }
}

enum DecisionKind: String, Codable, CaseIterable, Identifiable {
    case choice
    case noul
    case score

    var id: String { rawValue }
    var title: String {
        switch self {
        case .choice: return "选择题"
        case .noul: return "是非题"
        case .score: return "等级评分"
        }
    }
    var hint: String {
        switch self {
        case .choice: return "从多个候选方案中选出最符合要求的一项"
        case .noul: return "判断一个明确的问题是否成立"
        case .score: return "对有顺序的等级进行评分，起始级别为 0"
        }
    }
}

struct DecisionOption: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String
}

struct DecisionQuestion: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var kind: DecisionKind
    var instructions: String
    var options: [DecisionOption] = []

    static func make(_ kind: DecisionKind) -> DecisionQuestion {
        switch kind {
        case .choice:
            return DecisionQuestion(kind: .choice,
                                    instructions: "应当优先采用哪种处理方式？",
                                    options: [DecisionOption(text: "优先处理并联系客户"),
                                              DecisionOption(text: "进入常规处理队列"),
                                              DecisionOption(text: "无需进一步处理")])
        case .noul:
            return DecisionQuestion(kind: .noul,
                                    instructions: "客户是否明确表示可能取消服务？")
        case .score:
            return DecisionQuestion(kind: .score,
                                    instructions: "这件事的紧急程度是多少？",
                                    options: [DecisionOption(text: "可以稍后处理"),
                                              DecisionOption(text: "需要尽快处理"),
                                              DecisionOption(text: "必须立即处理")])
        }
    }
}

struct DecisionDraft: Codable, Equatable {
    var state: String
    var questions: [DecisionQuestion]

    static let example = DecisionDraft(
        state: "用户反馈三月份的费用被重复扣除，已联系过客服。用户要求今天退回重复费用，否则将取消订阅服务。",
        questions: [DecisionQuestion.make(.choice),
                    DecisionQuestion.make(.noul),
                    DecisionQuestion.make(.score)]
    )
}

struct ProbabilityItem: Identifiable {
    let id: String
    let label: String
    let probability: Double
}

struct DecisionAnswer: Identifiable {
    let id: String
    let title: String
    let kind: DecisionKind
    let selectedLabel: String?
    let score: Double?
    let confidence: Double?
    let probabilityItems: [ProbabilityItem]
}

struct DecisionValidationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum DecisionJSONBuilder {
    static let labels = Array("ABCDEFGH").map { String($0) }

    static func jsonString(_ text: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [text], options: [.fragmentsAllowed])
        let output = String(decoding: data, as: UTF8.self)
        return String(output.dropFirst().dropLast())
    }

    static func stateJSON(for input: String) throws -> String {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw DecisionValidationError(message: "请先输入背景信息。")
        }
        if let data = cleaned.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            return cleaned
        }
        return try jsonString(cleaned)
    }

    static func questionsJSON(for questions: [DecisionQuestion]) throws -> String {
        guard !questions.isEmpty else {
            throw DecisionValidationError(message: "请至少添加一道决策问题。")
        }
        var encoded: [String] = []
        for (questionIndex, question) in questions.enumerated() {
            let text = question.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw DecisionValidationError(message: "第 \(questionIndex + 1) 道题还没有填写问题描述。")
            }
            var members = ["\"type\":\(try jsonString(question.kind.rawValue))",
                           "\"instructions\":\(try jsonString(text))"]
            if question.kind != .noul {
                let options = question.options.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard options.count >= 2 && options.count <= 8 else {
                    throw DecisionValidationError(message: "第 \(questionIndex + 1) 道题需有 2～8 个选项或等级。")
                }
                guard options.allSatisfy({ !$0.isEmpty }) else {
                    throw DecisionValidationError(message: "第 \(questionIndex + 1) 道题存在空白选项。")
                }
                let criteria: String
                if question.kind == .choice {
                    let pairs = try options.enumerated().map { index, option in
                        "\(try jsonString(labels[index])):\(try jsonString(option))"
                    }
                    criteria = "{" + pairs.joined(separator: ",") + "}"
                } else {
                    criteria = "[" + (try options.map(jsonString)).joined(separator: ",") + "]"
                }
                members.append("\"criteria\":\(criteria)")
            }
            encoded.append("\(try jsonString("q\(questionIndex + 1)")):{\(members.joined(separator: ","))}")
        }
        return "{" + encoded.joined(separator: ",") + "}"
    }

    static func displayAnswers(_ raw: [String: Any], draft: DecisionDraft) -> [DecisionAnswer] {
        guard let answers = raw["answers"] as? [String: Any] else { return [] }
        return draft.questions.enumerated().compactMap { index, question in
            let key = "q\(index + 1)"
            guard let answer = answers[key] as? [String: Any] else { return nil }
            let confidence = (answer["confidence"] as? NSNumber)?.doubleValue
            var rows: [ProbabilityItem] = []
            var selected: String? = nil
            var score: Double? = nil
            switch question.kind {
            case .choice:
                let probs = answer["probabilities"] as? [String: Any] ?? [:]
                for (optionIndex, option) in question.options.enumerated() {
                    let name = labels[optionIndex]
                    let prob = (probs[name] as? NSNumber)?.doubleValue ?? 0
                    rows.append(ProbabilityItem(id: name, label: "\(name) · \(option.text)", probability: prob))
                }
                if let selectedName = answer["choice"] as? String,
                   let selectedIndex = labels.firstIndex(of: selectedName),
                   selectedIndex < question.options.count {
                    selected = "\(selectedName) · \(question.options[selectedIndex].text)"
                } else {
                    selected = answer["choice"] as? String
                }
            case .noul:
                let probability = max(0, min(1, (answer["noul"] as? NSNumber)?.doubleValue ?? 0))
                rows = [ProbabilityItem(id: "yes", label: "是", probability: probability),
                        ProbabilityItem(id: "no", label: "否", probability: 1 - probability)]
                selected = probability >= 0.5 ? "倾向于：是" : "倾向于：否"
            case .score:
                let probs = answer["probabilities"] as? [String: Any] ?? [:]
                for (optionIndex, option) in question.options.enumerated() {
                    let name = String(optionIndex)
                    let prob = (probs[name] as? NSNumber)?.doubleValue ?? 0
                    rows.append(ProbabilityItem(id: name, label: "\(name) 级 · \(option.text)", probability: prob))
                }
                score = (answer["score"] as? NSNumber)?.doubleValue
                if let score {
                    selected = String(format: "加权评分 %.2f / %d", score, max(0, question.options.count - 1))
                }
            }
            return DecisionAnswer(id: key, title: question.instructions, kind: question.kind,
                                  selectedLabel: selected, score: score, confidence: confidence,
                                  probabilityItems: rows)
        }
    }
}

@MainActor
final class DecisionViewModel: ObservableObject {
    @Published var draft: DecisionDraft = DecisionViewModel.restore() {
        didSet { storeDraft() }
    }
    @Published var status: String = "正在准备本地模型…"
    @Published var isLoading = false
    @Published var isPredicting = false
    @Published var isReady = false
    @Published var engineName: String = ""
    @Published var duration: Double? = nil
    @Published var answers: [DecisionAnswer] = []
    @Published var rawResult: String = ""

    private var agent: LayaAgent?
    private static let storageKey = "laya.decision.draft.v1"

    private static func restore() -> DecisionDraft {
        guard let stored = UserDefaults.standard.data(forKey: storageKey),
              let draft = try? JSONDecoder().decode(DecisionDraft.self, from: stored) else {
            return .example
        }
        return draft
    }

    private func storeDraft() {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func addQuestion(_ kind: DecisionKind) {
        guard draft.questions.count < 8 else {
            status = "最多同时处理 8 道题，请先删除已有问题。"
            return
        }
        draft.questions.append(.make(kind))
    }

    func removeQuestion(_ id: UUID) {
        draft.questions.removeAll { $0.id == id }
    }

    func resetExample() {
        draft = .example
        answers = []
        rawResult = ""
        duration = nil
    }

    func loadModel() {
        guard !isLoading, !isReady else { return }
        isLoading = true
        status = "正在加载模型（Metal / Candle）…"
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                guard let path = ModelLocator.find() else {
                    await MainActor.run {
                        self.status = "没有找到随 App 打包的模型权重。"
                        self.isLoading = false
                    }
                    return
                }
                let startedAt = Date()
                let newAgent = try LayaAgent(modelPath: path.path)
                try newAgent.warmUp()
                let time = Date().timeIntervalSince(startedAt) * 1000
                await MainActor.run {
                    self.agent = newAgent
                    self.engineName = newAgent.backendName
                    self.isReady = true
                    self.isLoading = false
                    self.status = String(format: "已就绪 · %@ · %.0f ms", newAgent.backendName, time)
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.status = "模型加载失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func predict() {
        guard let agent = agent, !isPredicting else { return }
        let snapshot = draft
        let stateJSON: String
        let questionsJSON: String
        do {
            stateJSON = try DecisionJSONBuilder.stateJSON(for: snapshot.state)
            questionsJSON = try DecisionJSONBuilder.questionsJSON(for: snapshot.questions)
        } catch {
            status = error.localizedDescription
            return
        }
        isPredicting = true
        status = "正在手机本地进行 \(snapshot.questions.count) 项决策…"
        answers = []
        duration = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let startedAt = Date()
                let response = try agent.predict(stateJSON: stateJSON, questionsJSON: questionsJSON)
                let elapsed = Date().timeIntervalSince(startedAt) * 1000
                let readable = try JSONSerialization.data(withJSONObject: response,
                                                          options: [.prettyPrinted, .sortedKeys])
                let text = String(decoding: readable, as: UTF8.self)
                let cards = DecisionJSONBuilder.displayAnswers(response, draft: snapshot)
                await MainActor.run {
                    self.answers = cards
                    self.rawResult = text
                    self.duration = elapsed
                    self.isPredicting = false
                    self.status = String(format: "已完成 %d 道决策 · %.1f ms", cards.count, elapsed)
                }
            } catch {
                await MainActor.run {
                    self.isPredicting = false
                    self.status = "决策失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

private struct DecisionQuestionEditor: View {
    @Binding var question: DecisionQuestion
    let index: Int
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("问题 \(index + 1)")
                    .font(.headline)
                Spacer()
                Menu {
                    ForEach(DecisionKind.allCases) { kind in
                        Button(kind.title) { changeType(to: kind) }
                    }
                } label: {
                    Label(question.kind.title, systemImage: "chevron.down")
                        .font(.subheadline)
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("删除问题 \(index + 1)")
            }
            TextField("填写这道题要判断什么", text: $question.instructions, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.never)
            Text(question.kind.hint)
                .font(.caption)
                .foregroundStyle(.secondary)

            if question.kind != .noul {
                VStack(spacing: 10) {
                    ForEach(Array(question.options.indices), id: \.self) { i in
                        HStack(alignment: .center) {
                            Text(question.kind == .choice ? DecisionJSONBuilder.labels[i] : "\(i)")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 25, alignment: .leading)
                            TextField("\(question.kind == .choice ? "选项" : "等级") \(i + 1)",
                                      text: $question.options[i].text,
                                      axis: .vertical)
                                .lineLimit(1...3)
                                .textInputAutocapitalization(.never)
                            if question.options.count > 2 {
                                Button {
                                    question.options.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    if question.options.count < 8 {
                        Button {
                            question.options.append(DecisionOption(text: ""))
                        } label: {
                            Label(question.kind == .choice ? "添加选项" : "添加等级", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 7)
    }

    private func changeType(to next: DecisionKind) {
        if question.kind != next {
            let oldText = question.instructions
            question = .make(next)
            if !oldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                question.instructions = oldText
            }
        }
    }
}

private struct ProbabilityRowView: View {
    let item: ProbabilityItem
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.label).font(.subheadline)
                Spacer(minLength: 10)
                Text(String(format: "%.1f%%", max(0, min(1, item.probability)) * 100))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.17))
                    Capsule().fill(Color.accentColor)
                        .frame(width: max(0, proxy.size.width * CGFloat(max(0, min(1, item.probability)))))
                }
            }
            .frame(height: 8)
            .accessibilityLabel("\(item.label)，概率 \(Int(item.probability * 100)) 百分比")
        }
    }
}

private struct DecisionAnswerCard: View {
    let answer: DecisionAnswer
    let ordinal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("问题 \(ordinal) · \(answer.kind.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(answer.title).font(.headline)
                }
                Spacer()
            }
            if let selected = answer.selectedLabel {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(selected).font(.subheadline.weight(.semibold))
                }
            }
            ForEach(answer.probabilityItems) { item in
                ProbabilityRowView(item: item)
            }
            if let confidence = answer.confidence {
                Text(String(format: "模型置信度指标：%.3f", confidence))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct DecisionHomeView: View {
    @StateObject private var model = DecisionViewModel()
    @State private var showRaw = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label(model.isReady ? "本机模型已就绪" : "本机模型初始化中", systemImage: "cpu")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(model.isReady ? Color.green : Color.secondary)
                        Text(model.status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if !model.isReady && !model.isLoading {
                            Button("重新加载模型") { model.loadModel() }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("01  背景信息")
                            .font(.headline)
                        Text("用中文描述当前情况，也可以粘贴一段 JSON、邮件或对话。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $model.draft.state)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 135)
                            .padding(9)
                            .background(Color.gray.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("02  决策问题")
                                .font(.headline)
                            Spacer()
                            Menu {
                                Button("选择题 · Choice", systemImage: "list.bullet.circle") { model.addQuestion(.choice) }
                                Button("是非题 · Noul", systemImage: "checkmark.circle") { model.addQuestion(.noul) }
                                Button("等级评分 · Score", systemImage: "chart.bar") { model.addQuestion(.score) }
                            } label: {
                                Label("添加问题", systemImage: "plus")
                            }
                            .disabled(model.draft.questions.count >= 8)
                        }
                        ForEach(Array(model.draft.questions.indices), id: \.self) { index in
                            DecisionQuestionEditor(question: $model.draft.questions[index], index: index) {
                                let id = model.draft.questions[index].id
                                model.removeQuestion(id)
                            }
                            if index < model.draft.questions.count - 1 {
                                Divider()
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        Button {
                            model.predict()
                        } label: {
                            HStack {
                                if model.isPredicting {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "bolt.fill")
                                }
                                Text(model.isPredicting ? "正在本地计算…" : "执行决策")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.isReady || model.isPredicting)

                        Button("恢复示例") { model.resetExample() }
                            .font(.footnote)
                    }

                    if !model.answers.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("03  决策结果").font(.headline)
                                Spacer()
                                if let elapsed = model.duration {
                                    Text(String(format: "%.1f ms", elapsed))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ForEach(Array(model.answers.indices), id: \.self) { index in
                                DecisionAnswerCard(answer: model.answers[index], ordinal: index + 1)
                            }
                            Text("概率代表模型估计，并非经独立验证的正确率。中文理解和复杂判断仍可能出错。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            DisclosureGroup("查看原始 JSON", isExpanded: $showRaw) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(model.rawResult)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    #if os(iOS)
                                    Button("复制 JSON") { UIPasteboard.general.string = model.rawResult }
                                    #endif
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                    Text("Laya Multilingual · 322M · Candle + Metal · 纯离线文字决策（当前版本不支持图片）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding()
            }
            .navigationTitle("Laya 决策")
            .navigationBarTitleDisplayMode(.inline)
            .task { model.loadModel() }
        }
    }
}