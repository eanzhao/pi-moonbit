# AGENTS.md — pi-moonbit

> AI agent guidance for working on this repository. See also [CLAUDE.md](CLAUDE.md).

## What is pi-moonbit?

A MoonBit reimplementation of [pi-mono](https://github.com/badlogic/pi-mono), the AI agent
toolkit by Mario Zechner. This is a study project: learn MoonBit by rebuilding a real-world
AI coding agent from scratch.

## For AI Agents Working on This Repo

### Build & Test

```bash
moon check          # Type check all packages
moon build          # Build
moon test           # Run all tests
moon test lib/ai    # Run tests for a specific package
```

### Reference Material

- `pi-mono/` contains the original TypeScript implementation (gitignored, read-only)
- `docs/` contains numbered architecture documents explaining each phase
- When implementing a package, read the corresponding pi-mono source first:
  - `lib/ai` → `pi-mono/packages/ai/src/`
  - `lib/agent` → `pi-mono/packages/agent/src/`
  - etc.

### Implementation Rules

1. **Follow the dependency order**: ai, tui (parallel leaves) → agent → coding_agent → main
2. **One doc + one commit per phase**: each phase adds a `docs/NN-*.md` and the implementation
3. **MoonBit idioms over TypeScript transliteration**:
   - Use `struct` for data-only types (options, config, results)
   - Use `enum` (ADT) for closed discriminated unions (Message, Event, StopReason)
   - Use `trait` / `pub(open) trait` for behavioral abstractions (Provider, Component)
   - Use newtype wrappers (`type ApiId String`) for open/extensible identifiers
   - Use `Result[T, E]` for error handling
   - Use pattern matching
4. **Tests**: every package should have `*_test.mbt` files with `test` blocks
5. **Do not modify** anything under `pi-mono/` — it is the read-only reference
6. **Target**: Native (primary), WASM only for web_ui

### Package Structure

Each package under `lib/` follows this layout:

```
lib/ai/
├── moon.pkg          # Package manifest (dependencies, etc.)
├── types.mbt         # Core type definitions
├── provider.mbt      # Provider trait and implementations
├── stream.mbt        # Streaming API
├── *_test.mbt        # Tests
└── ...
```

### Naming Conventions

- Packages: `snake_case` (e.g., `coding_agent`)
- Types/Enums: `PascalCase` (e.g., `Message`, `StopReason`)
- Functions/methods: `snake_case` (e.g., `stream_simple`)
- Constants: `snake_case` or `UPPER_CASE`
- Test names: descriptive strings in `test "..."` blocks
