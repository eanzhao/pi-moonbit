# pi-moonbit

MoonBit reimplementation of [pi-mono](https://github.com/badlogic/pi-mono) — an AI agent toolkit.

## What is this?

A learning project that rebuilds pi-mono's architecture in MoonBit, package by package:

| Package | Status | Description |
|---------|--------|-------------|
| `lib/ai` | Planned | Unified multi-provider LLM API |
| `lib/agent` | Planned | Agent loop, tool calling, state management |
| `lib/tui` | Planned | Terminal UI with differential rendering |
| `lib/coding_agent` | Planned | Coding agent with built-in tools and extensions |
| `lib/web_ui` | Planned | Web chat UI components (WASM) |
| `lib/mom` | Planned | Slack bot integration |
| `lib/pods` | Planned | GPU pod management for vLLM |

## Why?

- **Learn MoonBit** through a real-world, non-trivial project
- **Understand pi-mono's architecture** by reimplementing it from scratch
- **Explore MoonBit's strengths** in systems with complex type hierarchies (ADTs, traits, pattern matching)

## Prerequisites

- [MoonBit toolchain](https://www.moonbitlang.com/download/) (v0.1.x+)

## Build

```bash
moon check    # Type check
moon build    # Build
moon test     # Run tests
```

## Project Structure

```
pi-moonbit/
├── moon.mod.json         # Module definition
├── docs/                 # Architecture docs (one per implementation phase)
│   └── 00-project-overview.md
├── lib/                  # Library packages
│   ├── ai/               # LLM provider abstraction
│   ├── agent/            # Agent loop engine
│   ├── tui/              # Terminal UI library
│   ├── coding_agent/     # Coding agent core
│   └── ...
└── src/                  # Executables
    └── main/             # CLI entry point
```

## Docs

Each implementation phase has a corresponding document in `docs/`:

- [00 - Project Overview](docs/00-project-overview.md) — Architecture analysis and implementation plan

## Reference

- [pi-mono](https://github.com/badlogic/pi-mono) — Original TypeScript implementation
- [MoonBit docs](https://docs.moonbitlang.com/) — Language reference
