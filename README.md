# pi-moonbit

A MoonBit reimplementation of [pi-mono](https://github.com/badlogic/pi-mono) — an AI coding agent toolkit. The CLI binary is `pimbt`.

> 中文版：[README.zh-CN.md](README.zh-CN.md)

## What is this?

pi-mono is an AI agent toolkit written in TypeScript by Mario Zechner (creator of libGDX). pi-moonbit is a from-scratch rewrite in MoonBit, aimed at:

- **Learning MoonBit** — building a real project to exercise its type system, traits, generics, and pattern matching.
- **Learning the architecture** — rebuilding each package top to bottom to understand how an AI agent is structured from the LLM API layer up to the interactive UI.

## Current status

**All 26 planned issues closed.** 343 tests passing. ~30K lines of MoonBit.

| Package | Status | Notes |
|---|---|---|
| `lib/ai` | ✅ complete | 7 LLM providers (OpenAI / Anthropic / Mistral / Gemini / Bedrock / Vertex / Azure), NyxID gateway, OAuth + PKCE primitives, env-api-keys, model registry, overflow detection |
| `lib/tui` | ✅ complete | `Component` trait, diff rendering, component library (Input / SelectList / Loader / Box / Container), Markdown rendering, fuzzy search, autocomplete, undo stack |
| `lib/agent` | ✅ complete | Agent engine: turn loop, three-phase tool execution, event system, steering / follow-up queues |
| `lib/coding_agent` | ✅ complete | Session tree, compaction, extension system, 6 built-in tools, slash commands, skills, HTML export, path / mime / git / frontmatter utilities |
| `lib/cli` (→ `pimbt`) | ✅ complete | 3 modes (Print / Interactive / RPC), multi-target (JS / Native / WASM), theme system, **NyxID login + auto token refresh + providers management** |
| `lib/web_ui` | ✅ complete | Web transcript, storage, 6 dialogs, 12 artifact types, tool renderers, IndexedDB backend interface |
| `lib/mom` | ✅ complete | Platform-neutral channel model, Slack adapter, event loop / timer / watcher / host driver |
| `lib/pods` | ✅ complete | `PodRegistry`, SSH/SCP command builders, vLLM deployment commands |

## Install

### Prerequisites

- [MoonBit toolchain](https://www.moonbitlang.com/download/)
- Node.js 18+ (pimbt runs on the JS target)

### One-liner

```bash
git clone https://github.com/eanzhao/pi-moonbit.git
cd pi-moonbit
./scripts/install.sh
```

Installs to `~/.local/bin/pimbt` by default. Add `~/.local/bin` to your `PATH` and you're set.

Other options:

```bash
PREFIX=/usr/local ./scripts/install.sh   # system-wide install (may need sudo)
./scripts/install.sh --symlink           # dev mode: symlink main.js so moon build updates it live
./scripts/install.sh --uninstall         # remove pimbt
```

After install:

```bash
pimbt --help
pimbt login                              # browser-based NyxID login
pimbt providers connect openai           # paste an LLM API key
pimbt --api nyxid-gateway --model gpt-4o "hello"
```

## Using pimbt with NyxID (recommended)

[NyxID](https://nyx.chrono-ai.fun) is a credential-brokering LLM gateway. You store your LLM provider keys (OpenAI / Anthropic / Gemini / Mistral / ...) once in NyxID's panel; pimbt authenticates with NyxID over OAuth and proxies every LLM call through the gateway. **pimbt never sees raw LLM API keys.**

Benefits:

- One login, use every provider you've configured on NyxID.
- Keys sit server-side — easier to rotate or revoke.
- Works across devices — no `export OPENAI_API_KEY=...` sprinkled everywhere.

### Register on NyxID

NyxID currently requires an invite code:

- Register at <https://nyx.chrono-ai.fun/register>
- Invite code: `NYX-S6SBEA4X` (20 seats, first-come)

### First-run flow

```bash
# 1. Browser-based login (no client_id needed — uses NyxID's CLI auth flow)
pimbt login

# 2. Self-check shows whether you have any providers configured. If not:
pimbt providers connect openai       # prompts for your sk-... key
pimbt providers connect anthropic    # or: --api-key sk-ant-... to skip the prompt

# 3. Inspect what's connected
pimbt providers list
pimbt models                         # full provider + model-id listing

# 4. Talk to a model — NyxID routes by model id automatically
pimbt --api nyxid-gateway --model gpt-4o "write a fib function"
pimbt --api nyxid-gateway --model claude-sonnet-4-5-20250929 "explain quicksort"
```

`--model` accepts any model id NyxID knows about for a provider you've connected. pimbt does not hard-code a model whitelist.

## Using pimbt with direct provider keys

If you'd rather skip NyxID and manage keys yourself:

```bash
export OPENAI_API_KEY=sk-...
pimbt --api openai-responses --model gpt-4o "hello"

export ANTHROPIC_API_KEY=sk-ant-...
pimbt --api anthropic-messages --model claude-sonnet-4-5 "hello"

export GOOGLE_API_KEY=...
pimbt --api google-generativeai --model gemini-2.0-flash "hello"

export MISTRAL_API_KEY=...
pimbt --api mistral-conversation --model mistral-large-latest "hello"
```

## Developer commands

```bash
moon check          # type check
moon build          # compile
moon test           # run all tests
moon test lib/ai    # run tests for one package

# Run the CLI without installing
moon run src/main --target js -- --help
```

## Project layout

```
pi-moonbit/
├── moon.mod.json
├── docs/                  # design docs, one per phase
├── lib/
│   ├── ai/                # Phase 01 — LLM provider abstraction
│   ├── tui/               # Phase 02 — terminal UI library
│   ├── agent/             # Phase 03 — agent loop engine
│   ├── coding_agent/      # Phase 04 — coding-agent core
│   ├── web_ui/            # Phase 06 — web UI support layer
│   ├── mom/               # Phase 07 — mom runtime
│   ├── pods/              # GPU pod management
│   └── cli/               # Phase 05 — pimbt CLI implementation
├── src/main/              # pimbt entry point (thin shell over lib/cli)
├── scripts/install.sh     # local installer
└── pi-mono/               # original TypeScript reference (gitignored, read-only)
```

## Architecture docs

Each phase has a design doc explaining what was built, why, and how it differs from pi-mono:

- [00 — Project overview](docs/00-project-overview.md) — architecture analysis and implementation plan
- [01 — LLM API layer](docs/01-ai.md) — messages, models, providers, streaming events
- [02 — Terminal UI](docs/02-tui.md) — component system, diff rendering, keyboard input
- [03 — Agent engine](docs/03-agent.md) — turn loop, tool execution, events and state
- [04 — Coding agent](docs/04-coding-agent.md) — session management, extension system, built-in tools
- [05 — CLI entry](docs/05-cli.md) — arg parsing, multi-session JSONL, continue/resume, REPL
- [06 — Web UI support](docs/06-web-ui.md) — web transcript, storage, artifacts, tool renderers
- [07 — Mom runtime](docs/07-mom.md) — unified channel model, Slack adapter

## References

- [pi-mono](https://github.com/badlogic/pi-mono) — original TypeScript implementation
- [NyxID](https://github.com/eanzhao/NyxID) — credential broker / OAuth IdP
- [MoonBit docs](https://docs.moonbitlang.com/) — language reference

## License

MIT
