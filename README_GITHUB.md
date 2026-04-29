# OpenClaw Grounding Guard v3.1 (GitHub Distribution)

A self-contained OpenClaw Hook Pack to reduce hallucinations via grounding, source/confidence enforcement, and post-send audit.

## What is included

- L1 pre-processor hook (`message:preprocessed`)
- L3 post-processor hook (`message:sent`)
- L2 tools: `search_local`, `search_web`, `verify_fact`
- Config template: `config/example.json`
- Docs: architecture, config, install, execution spec 3.1, harness mapping
- MIT license

## Install

```bash
openclaw hooks install .
cp config/example.json ~/.openclaw/grounding-guard.json
openclaw hooks list
```

Optional web search:

```bash
export TAVILY_API_KEY="your-api-key"
```

## Quick verification

```bash
node -e "import('./src/hooks/grounding-pre-processor/handler.js').then(()=>console.log('pre ok'))"
node -e "import('./src/hooks/grounding-post-processor/handler.js').then(()=>console.log('post ok'))"
node -e "const t=require('./src/tools/grounding-tools.cjs'); console.log(Object.keys(t).join(','))"
```

Expected output:
- `pre ok`
- `post ok`
- `search_local,search_web,verify_fact`
