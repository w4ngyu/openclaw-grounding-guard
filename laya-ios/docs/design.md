# Laya iPhone 中文决策 App — 2026-11-13

## Outcome

Replace the read-only benchmark demo with a native Chinese decision tool while retaining the proven `LayaKit` + `Candle/Metal` inference path and the bundled 322M multilingual checkpoint.

## UI

- A single editable background/state field, accepting natural language or JSON.
- Up to eight editable decisions, each typed as `choice`, `noul`, or `score`, with editable instructions.
- Choice: 2–8 labeled options A–H. Score: 2–8 ordered levels starting at 0. Noul: yes/no question without criteria.
- True model outputs displayed as readable cards, per-option probability bars, and expected weighted score; raw JSON is optional.
- Persist drafts locally in UserDefaults; no network/API calls; auto-load the bundled model without synthetic benchmark runs.

## Validation

`DecisionJSONBuilder.questionsJSON` preserves insertion/option order using explicit JSON text instead of Swift dictionaries, which matters to the Laya tokenization/prompt implementation. `stateJSON` handles JSON and natural language. The interpretation of `confidence` is stated as a model metric, not calibrated accuracy.

## Non-goals

No image input (Laya Multilingual 322M is text-only). No cloud inference, persistent background inference, or guaranteed accuracy on Chinese tasks. Preserve underlying app structure and model assets.

## Build integration

Clone `TJamesWilliams/laya-r-mlx` at the previously tested commit, replace `swift/LayaDemo/Sources/LayaDemoApp.swift`, compile `LayaKit` XCFramework, bundle multilingual checkpoint, generate Xcode project, and export unsigned IPA. Build provenance and on-device test remain separate.