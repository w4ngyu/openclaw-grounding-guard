import Foundation

@main
struct DecisionJSONTests {
    static func main() throws {
        let sample = try DecisionDocumentJSON.parse(DecisionDocumentJSON.sample)
        assert(sample.questions.count == 1)
        assert(sample.questions[0].kind == "choice")
        assert(sample.questions[0].options == ["6", "8", "9", "12"])

        let three = """
        {
          "state": "用户明天需要确定处理方案",
          "questions": [
            {"type":"choice","instructions":"选什么？","criteria":["先处理","后处理"]},
            {"type":"noul","instructions":"是否有截止日期？"},
            {"type":"score","instructions":"优先级？","criteria":["低","中","高"]}
          ]
        }
        """
        let parsed = try DecisionDocumentJSON.parse(three)
        assert(parsed.questions.count == 3)
        assert(parsed.questions.map(\.kind) == ["choice", "noul", "score"])
        assert(parsed.questions[1].options.isEmpty)
        let exported = try DecisionDocumentJSON.export(parsed)
        let roundTripped = try DecisionDocumentJSON.parse(exported)
        assert(roundTripped == parsed)

        let object = """
        {
          "state":"一段中文状态",
          "question_order":["q2","q1"],
          "questions":{
            "q1":{"type":"noul","instructions":"最后一道题？"},
            "q2":{"type":"choice","instructions":"第一道题？",
                  "criteria":{"A":"苹果","B":"香蕉","C":"西瓜"},
                  "criteria_order":["C","A","B"]}
          }
        }
        """
        let ordered = try DecisionDocumentJSON.parse(object)
        assert(ordered.questions.map(\.instructions) == ["第一道题？", "最后一道题？"])
        assert(ordered.questions[0].options == ["西瓜", "苹果", "香蕉"])

        let stringEscapes = """
        {"state":"中文：\\\\\\"测试\\\\\\"\\\\n换行","questions":[
          {"type":"noul","instructions":"包含引号？"}]}
        """
        let escaped = try DecisionDocumentJSON.parse(stringEscapes)
        assert(escaped.questions.count == 1)

        let invalidInputs = [
            "{}",
            #"{"state":"","questions":[]}"#,
            #"{"state":"test","questions":[]}"#,
            #"{"state":"test","questions":[{"type":"choice","instructions":"test","criteria":["only"]}]}"#,
            #"{"state":"test","questions":[{"type":"noul","instructions":"test","criteria":["yes","no"]}]}"#,
            #"{"state":"test","questions":[{"type":"choice","instructions":"test","criteria":["","valid"]}]}"#,
            #"{"state":"test","questions":[{"type":"unknown","instructions":"test"}]}"#
        ]
        for bad in invalidInputs {
            var didThrow = false
            do { _ = try DecisionDocumentJSON.parse(bad) } catch { didThrow = true }
            assert(didThrow, "Expected input validation failure for: \(bad)")
        }

        print("DecisionDocumentJSON tests passed")
    }
}
