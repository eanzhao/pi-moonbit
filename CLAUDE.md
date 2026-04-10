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
- Use `struct` for data-only types (options, config, results)
- Use `enum` (ADT) for closed discriminated unions (Message, Event, StopReason)
- Use `trait` (or `pub(open) trait`) for behavioral abstractions (Provider, Component)
- Use newtype wrappers (e.g., `type ApiId String`) for open/extensible identifiers
- Use `Result[T, E]` and `!` syntax for error handling
- Prefer pattern matching over if/else chains
- Write tests in `*_test.mbt` files using `test` blocks

### Workflow

- Each implementation phase = one numbered doc + one commit
- Docs live in `docs/` with `NN-topic.md` naming
- Implementation order follows dependency graph: ai, tui (parallel) → agent → coding_agent → main
- Package config uses `moon.pkg` format (not `moon.pkg.json`)
- Reference the TypeScript source in `pi-mono/packages/` when implementing

### Commit Messages

Use conventional commits:

```
feat(ai): add Message enum and Provider trait
docs(00): project overview and architecture plan
feat(agent): implement agent loop with tool calling
```

## Key Design Decisions

- **Data interfaces → `struct`**: StreamOptions, Tool (schema), Context, ThinkingBudgets
- **Behavioral interfaces → `trait`**: Provider (`stream()`), Component (`render()`), Extension
- **Closed union types → `enum` (ADT)**: Message, AssistantMessageEvent, StopReason
- **Open union types → newtype `String` + registry**: Api, Provider identifiers
- **Declaration merging → registry pattern**: CustomAgentMessages uses a deserializer map
- **TypeScript generics → MoonBit generics with trait bounds**
- **npm workspaces → MoonBit single-module multi-package**
- **async/await + AsyncIterable → `async fn` (Native) or callbacks (fallback)**
- **JSON serialization → `@json` library**
- **Target**: Native (primary), WASM (for web_ui only)

## Reference: pi-mono Architecture

The original pi-mono has 7 packages with this dependency graph (from package.json):

```
叶子:  ai          tui          (无内部依赖)
       ↓            ↓
中间:  agent→ai    web-ui→ai,tui   pods→agent
       ↓
上层:  coding-agent → ai, agent, tui
       ↓
       mom → ai, agent, coding-agent
```

Key abstractions to port:
- `Provider` (ai): LLM provider with `stream()` / `complete()`
- `AgentLoop` (agent): orchestrates LLM calls and tool execution
- `AgentTool` (agent): tool definition with schema + execute
- `Component` (tui): UI element with `render()` + input handling
- `Extension` (coding-agent): plugin with lifecycle hooks
