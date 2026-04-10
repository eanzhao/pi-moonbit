# CLAUDE.md — pi-moonbit

## Project Overview

pi-moonbit is a MoonBit reimplementation of [pi-mono](https://github.com/badlogic/pi-mono),
an AI agent toolkit originally written in TypeScript. The reference implementation lives
in `pi-mono/` (gitignored — read-only reference, do not modify).

## Language & Toolchain

- **Language**: MoonBit
- **Toolchain**: `moon` CLI (v0.1.x+)
- **Build**: `moon check` / `moon build` / `moon test`
- **Module**: `eanzhao/pi-moonbit` (defined in `moon.mod.json`)

## Repository Layout

```
pi-moonbit/
├── moon.mod.json          # Module definition
├── docs/                  # Architecture docs (numbered, one per phase)
├── lib/                   # Library packages (mirror pi-mono's packages/)
│   ├── ai/                # ← pi-mono/packages/ai
│   ├── agent/             # ← pi-mono/packages/agent
│   ├── tui/               # ← pi-mono/packages/tui
│   ├── coding_agent/      # ← pi-mono/packages/coding-agent
│   ├── web_ui/            # ← pi-mono/packages/web-ui
│   ├── mom/               # ← pi-mono/packages/mom
│   └── pods/              # ← pi-mono/packages/pods
├── src/main/              # CLI entry point
└── pi-mono/               # Original TS reference (gitignored, read-only)
```

## Conventions

### MoonBit Style

- Package names use `snake_case` (e.g., `coding_agent`, `web_ui`)
- Types use `PascalCase`, functions/methods use `snake_case`
- Use `enum` (ADT) for discriminated unions (Message, Event, etc.)
- Use `trait` for abstraction points (Provider, Tool, Component)
- Use `Result[T, E]` and `!` syntax for error handling
- Prefer pattern matching over if/else chains
- Write tests in `*_test.mbt` files using `test` blocks

### Workflow

- Each implementation phase = one numbered doc + one commit
- Docs live in `docs/` with `NN-topic.md` naming
- Implementation order follows dependency graph: ai → agent → tui → coding_agent → main
- Reference the TypeScript source in `pi-mono/packages/` when implementing

### Commit Messages

Use conventional commits:

```
feat(ai): add Message enum and Provider trait
docs(00): project overview and architecture plan
feat(agent): implement agent loop with tool calling
```

## Key Design Decisions

- **TypeScript interfaces → MoonBit traits**: Provider, Tool, Component
- **TypeScript union types → MoonBit enum (ADT)**: Message, Event, StopReason
- **TypeScript generics → MoonBit generics with trait bounds**
- **npm workspaces → MoonBit single-module multi-package**
- **async/await → MoonBit Async or callback-based patterns**
- **JSON serialization → `@json` library**
- **Target**: WASM (primary) and Native

## Reference: pi-mono Architecture

The original pi-mono has 7 packages with this dependency graph:

```
ai (LLM API)  ←  agent (loop)  ←  coding-agent (CLI)  ←  mom (Slack)
                                        ↑
tui (terminal UI) ─────────────────────┘

web-ui (browser)  ←  ai, agent
pods (GPU)        ←  ai, agent
```

Key abstractions to port:
- `Provider` (ai): LLM provider with `stream()` / `complete()`
- `AgentLoop` (agent): orchestrates LLM calls and tool execution
- `AgentTool` (agent): tool definition with schema + execute
- `Component` (tui): UI element with `render()` + input handling
- `Extension` (coding-agent): plugin with lifecycle hooks
