# Honor of Kings: ACE / 王者万象棋 — Screenshot Decision Preset

Status: **screenshot analysis protocol + Laya JSON scaffold**; no image input is added to the iOS Laya 322M application.

## Workflow

1. The user uploads a live game screenshot into ChatGPT.
2. Identify visible facts: screen type, round, HP, energy, chessplayer and level, banned factions, units and their levels/equipment, shop choices, talent cards, auction lots, opponents, and remaining timer. Mark hidden details as **unknown**.
3. Only compare **currently legal moves**. Score near-term combat/survival, hero-combine and awakening growth, trait/keyword synergy, energy opportunity cost, higher-tier access through chessplayer level, future flexibility, and contested shared card pool.
4. Return the immediately actionable best pick, a backup, and one sentence for each; specify card/button and approximate location. Use qualitative certainty, never invent a win probability.
5. When requested, produce `state + questions` JSON from the screenshot for manual import into the existing Laya text-only app. It is a secondary comparison, **not** an image-based model.

## Current rules / provenance

- [English gameplay and economy rules](https://hokaceguide.com/rules/)
- [Unofficial English translation of Honor of Kings ACE beginner guide](https://lani27.github.io/hok-ace/guides/beginner-guide.html)

These are **third-party English references**, not a guarantee of the current live patch. Compare current screenshot card text and rule tooltips before using specific effects or meta tier lists.

## Constraints

No automated live screen monitoring or clicking. A single screenshot may omit important information; still give a provisional recommendation and request at most one additional view if it could reverse the decision. Do not assume standard auto-chess interest mechanics or standard star upgrades apply.
