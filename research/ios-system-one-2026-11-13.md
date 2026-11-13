# Offline Jev-like decision models on iPhone — 2026-11-13

## User outcome / acceptance

Run a **trained, typed-decision model** fully on an iPhone, with Chinese states/questions/criteria and a probability distribution for each answer. Required: `choice`, `noul`, `score`, an installable iOS package, offline inference, usable memory. Desired: photos and multiple pictures. **A chat LLM asked to choose A/B/C is not an equivalent implementation.** Accuracy on Chinese and probability calibration must be demonstrated, not inferred from the model name or leaderboard.

## Verified technical candidates

| Model | True typed decision model? | Media | Apple deployment evidence | Chinese quality | Real blockers |
|---|---|---|---|---|---|
| Laya Multilingual 322M | yes | text only | Rust/candle Metal XCFramework and SwiftUI demo, iPhone 17 Pro developer benchmark | native multilingual tokenizer/checkpoint; validate accuracy | 256-ish short context, text only; lower English decision benchmark quality; needs sideload signature |
| Valen-Decision 1.5 2B | yes, Mixer/decision head | text/image/video, bbox | Q8 GGUF plus vision bundle; **custom** llama.cpp runtime is validated on Linux x86-64, not iOS | Qwen3.5 based; no independent Chinese 2B accuracy verified | source patch + Metal/iOS build + on-device parity/memory |
| Valen-Decision 1.5 4B | yes | text/image/video, bbox | same runtime restrictions | no Chinese iOS decision accuracy verified | Q8 text 4.20 GiB + vision 1.24 GiB **before** runtime allocations |
| LiquidAI d1-omni-600M / CoreAIKit port | yes | text + pictures OR text + audio | native iPhone 17 Pro A19 Pro Core AI compiled bundles; Swift host; reported on-device parity | supports 15 languages in source metadata, task-calibrated Chinese accuracy unverified | iOS27 + increased-memory-limit signing entitlement; hosted bundles take several GB |
| decider-2b-vision / CoreAIKit | yes | text + pictures | iOS27 Swift host and device parity gate; developer tested on iPhone 18 Pro | Chinese task accuracy unverified | increased-memory-limit entitlement, option cap 10, large graph cache |
| QEV 2B | yes | text + image; source multi-image extension | released Python SDK; no verified iOS port | multilingual backbone, reported evaluation mainly English | entire trained readout/vision pipeline must be ported |

### Verified weights and memory facts

- Valen-Decision 1.5 **GGUF Q8** 0.8B: 0.77 GiB text + 0.37 GiB vision; 2B: 1.90 GiB + 1.23 GiB; 4B: 4.20 GiB + 1.24 GiB. This is storage, **not peak iPhone RAM**.
- Valen-Decision 1.5 ONNX q8-mlp bundle: 0.8B 2.758 GB; 2B 6.364 GB; 4B 11.766 GB download. Some modules remain fp32. ONNX Runtime supports iOS via Core ML EP, but operator partitioning and peak memory need measured testing. Standard llama.cpp or GGUF import apps do not implement Valen's custom decision readout.
- Valen public Decision Index 0.4.1: 2B text 61.89 / vision 70.54, 4B text 69.01 / vision 77.85. **These are normalized public-index scores, not accuracy percentages, and not Chinese or iPhone measurements**.
- d1-omni-600M Core AI port: native A19 Pro builds; author reports text ticket/3 questions 97 ms, image/3 questions 0.76 s on iPhone 17 Pro. This is not an independent audit or Chinese accuracy estimate. Precompiled models still need signing entitlement and app UX.
- Laya iPhone author reports 66 ms for four questions and 20 ms for one, on the 322M multilingual checkpoint. It does not handle images.

## Recommendation as of this snapshot

1. **Finish Laya IPA** to establish an entirely offline, reproducible baseline, rather than claim it is the accuracy winner.
2. **Portable multi-modal baseline**: inspect d1-omni-600M / CoreAIKit and verify whether the linked Apple developer profile permits `com.apple.developer.kernel.increased-memory-limit`; do not promise sideloading success without that entitlement.
3. **Highest-priority longer-term model port**: Valen-Decision 1.5 2B (text+vision) with its custom GGUF inference path; 4B follows only if measured 2B Chinese decision accuracy is insufficient and RAM allows. Alternative ONNX+CoreML EP if custom GGUF/Metal fails.
4. QEV remains a research comparison, not the first iOS implementation target.

## Required measured gates

- Build and install a signed IPA on the actual target iPhone; log OS/device, signature profile/entitlements, asset hashes.
- Force airplane mode after model download; confirm zero network use and correct predictions with text only and with image inputs.
- Repeat 30+ labeled **Chinese** tasks across noul/choice/score: natural language, long states, short states, swapped option ordering, same prompt in simplified/traditional Chinese, negation, ambiguity/abstention. Compare actual label accuracy, Brier/ECE, abstention/coverage. Do not treat raw confidence as correctness.
- Add 15+ image decisions with ground-truth labels and consistent image assets (single picture then two pictures). Measure decision-pipeline parity against upstream and inspect wrong results. User-specific scenes require separately consented real evaluation examples.
- Measure cold launch, warm latency, model footprint, peak resident memory / jetsam, battery and temperature.
- At least two checkpoints, same tasks, same input ordering and photo resolution; record source versions and pinned revision.

## Links / provenance (official English sources only)

- Laya Rust iOS: https://github.com/TJamesWilliams/laya-r-mlx
- This branch's active workflow: https://github.com/w4ngyu/openclaw-grounding-guard/blob/laya-iphone-build-20261113/.github/workflows/laya-iphone.yml
- Valen repo: https://github.com/Valen-Team/Valen
- Valen architecture: https://valen-team.github.io/docs/valen/architecture/
- Valen GGUF Q8 release and Linux-only validation: https://valen-team.github.io/docs/valen/gguf/
- Valen ONNX variants: https://valen-team.github.io/docs/valen/onnx/
- Public-index results: https://valen-team.github.io/docs/valen/decision-index/
- QEV project: https://github.com/ken-jo/qev
- CoreAIKit System One: https://john-rocky.github.io/coreai-kit/docs/SYSTEM_ONE.html
- Core AI d1 Omni 600M: https://huggingface.co/smdesai/d1-omni-600M-CoreAI
- Core AI visual decider: https://github.com/john-rocky/coreai-model-zoo/tree/main/apps/DeciderVision
- ONNX Runtime iOS and CoreML EP: https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html
