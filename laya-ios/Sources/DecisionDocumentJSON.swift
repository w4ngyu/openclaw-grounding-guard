import Foundation

struct ImportedDecisionQuestion: Equatable {
    let kind: String
    let instructions: String
    let options: [String]
}

struct ImportedDecisionDocument: Equatable {
    let state: String
    let questions: [ImportedDecisionQuestion]
}

struct DecisionDocumentImportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum DecisionDocumentJSON {
    static let sample = """
    {
      "state": "已知椭圆 x²/25 + y²/9 = 1，F₁、F₂ 为两个焦点，椭圆上的 P 满足 ∠F₁PF₂ = 90°。",
      "questions": [
        {
          "type": "choice",
          "instructions": "三角形 PF₁F₂ 的面积是多少？",
          "criteria": ["6", "8", "9", "12"]
        }
      ]
    }
    """
    static let maxBytes = 128 * 1024
    private static let maxQuestions = 8
    private static let maxOptions = 8

    static func parse(_ source: String) throws -> ImportedDecisionDocument {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw invalid("请先粘贴 JSON，或从文件选择 JSON。") }
        guard trimmed.utf8.count <= maxBytes else { throw invalid("JSON 不能超过 128 KB。") }
        guard let root = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] else {
            throw invalid("JSON 格式错误。需要包含 state 和 questions 的对象。")
        }
        guard let rawState = root["state"] else { throw invalid("缺少 state（背景信息）。") }
        let state: String
        if let text = rawState as? String {
            state = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if JSONSerialization.isValidJSONObject(rawState) {
            let data = try JSONSerialization.data(withJSONObject: rawState, options: [.prettyPrinted, .sortedKeys])
            state = String(decoding: data, as: UTF8.self)
        } else {
            throw invalid("state 只支持字符串、JSON 对象或数组。")
        }
        guard !state.isEmpty && state.count <= 16000 else {
            throw invalid("背景信息不能为空，且不能超过 16000 字符。")
        }

        guard let rawQuestions = root["questions"] else { throw invalid("缺少 questions（决策问题）。") }
        let nodes: [[String: Any]]
        if let array = rawQuestions as? [[String: Any]] {
            nodes = array
        } else if let object = rawQuestions as? [String: Any] {
            let keys = try orderedKeys(Array(object.keys), declared: root["question_order"], context: "question_order")
            nodes = try keys.map { key in
                guard let value = object[key] as? [String: Any] else {
                    throw invalid("问题 \(key) 必须是 JSON 对象。")
                }
                return value
            }
        } else {
            throw invalid("questions 必须是问题数组或标准 Laya 问题对象。")
        }
        guard !nodes.isEmpty && nodes.count <= maxQuestions else {
            throw invalid("每份 JSON 必须包含 1～8 道问题。")
        }

        let questions: [ImportedDecisionQuestion] = try nodes.enumerated().map { index, raw in
            let ordinal = index + 1
            guard let kind = raw["type"] as? String,
                  ["choice", "noul", "score"].contains(kind) else {
                throw invalid("第 \(ordinal) 题的 type 只能是 choice、noul、score。")
            }
            guard let instructions = raw["instructions"] as? String,
                  !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  instructions.count <= 2000 else {
                throw invalid("第 \(ordinal) 题缺少有效的 instructions（问题内容）。")
            }
            let options: [String]
            if kind == "noul" {
                if let criteria = raw["criteria"], !(criteria is NSNull) {
                    throw invalid("第 \(ordinal) 道是非题不能包含 criteria；请直接写判断问题。")
                }
                options = []
            } else {
                guard let criteria = raw["criteria"] else {
                    throw invalid("第 \(ordinal) 题缺少 criteria（选项或等级）。")
                }
                if let values = criteria as? [String] {
                    options = values
                } else if let dictionary = criteria as? [String: String] {
                    let keys: [String]
                    if kind == "score" && raw["criteria_order"] == nil {
                        keys = dictionary.keys.sorted {
                            if let a = Int($0), let b = Int($1) { return a < b }
                            return $0.localizedStandardCompare($1) == .orderedAscending
                        }
                    } else {
                        keys = try orderedKeys(Array(dictionary.keys),
                                               declared: raw["criteria_order"],
                                               context: "第 \(ordinal) 题 criteria_order")
                    }
                    options = keys.compactMap { dictionary[$0] }
                } else {
                    throw invalid("第 \(ordinal) 题的 criteria 必须是字符串数组或文字键值对象。")
                }
                guard options.count >= 2 && options.count <= maxOptions else {
                    throw invalid("第 \(ordinal) 题必须有 2～8 个选项或等级。")
                }
                guard options.allSatisfy({
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 500
                }) else {
                    throw invalid("第 \(ordinal) 题有空白或过长的选项。")
                }
            }
            return ImportedDecisionQuestion(kind: kind,
                                            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                                            options: options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        return ImportedDecisionDocument(state: state, questions: questions)
    }

    static func export(_ document: ImportedDecisionDocument) throws -> String {
        guard !document.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid("背景信息不能为空。")
        }
        let questions: [[String: Any]] = document.questions.map { item in
            var result: [String: Any] = ["type": item.kind, "instructions": item.instructions]
            if item.kind != "noul" { result["criteria"] = item.options }
            return result
        }
        let documentObject: [String: Any] = ["state": document.state, "questions": questions]
        let raw = try JSONSerialization.data(withJSONObject: documentObject, options: [.prettyPrinted, .sortedKeys])
        let json = String(decoding: raw, as: UTF8.self)
        _ = try parse(json)
        return json
    }

    private static func orderedKeys(_ keys: [String], declared: Any?, context: String) throws -> [String] {
        if let declared {
            guard let order = declared as? [String],
                  order.count == keys.count,
                  Set(order).count == keys.count,
                  Set(order) == Set(keys) else {
                throw invalid("\(context) 必须完整、无重复地列出所有键。")
            }
            return order
        }
        return keys.sorted { a, b in
            if let x = numericQuestionOrder(a), let y = numericQuestionOrder(b) { return x < y }
            if numericQuestionOrder(a) != nil { return true }
            if numericQuestionOrder(b) != nil { return false }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    private static func numericQuestionOrder(_ key: String) -> Int? {
        guard key.hasPrefix("q") else { return nil }
        return Int(key.dropFirst())
    }

    private static func invalid(_ message: String) -> DecisionDocumentImportError {
        DecisionDocumentImportError(message: message)
    }
}
