# Release Notes - v3.1.0

## Highlights

- Added harness-style checkpoint output (`groundingCheckpoint`) in L1.
- Added independent evaluator output (`groundingAudit`) in L3.
- Added web-search circuit breaker controls for long-running stability.
- Enforced source/confidence policy with structured issue codes (`GG-*`).
- Preserved OpenClaw hook boundary: post-send audit warning without mutating main response.

## Runtime model

- L1 (`message:preprocessed`): retrieve + inject grounding context.
- L2 tools: local/web retrieval and fact consistency check.
- L3 (`message:sent`): validate annotations, evaluate quality, append warning if needed.
