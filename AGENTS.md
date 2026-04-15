# AGENTS.md — pi-moonbit

> AI 助手工作指南。详细版见 [CLAUDE.md](CLAUDE.md)。

## 这是什么？

用 MoonBit 重写 [pi-mono](https://github.com/badlogic/pi-mono)（AI Agent 工具包）。
核心路径（Phase 01-05）已完成，67 个测试全部通过。

## 构建 & 测试

```bash
moon check          # 类型检查
moon build          # 编译
moon test           # 全部测试（67 个）
moon test lib/ai    # 指定包测试
```

## 项目结构

```
lib/ai/             # Phase 01 — LLM API 抽象
lib/tui/            # Phase 02 — 终端 UI 框架
lib/agent/          # Phase 03 — Agent 引擎
lib/coding_agent/   # Phase 04 — 编码助手核心
src/main/           # Phase 05 — CLI 入口（JS target 可运行）
docs/               # 架构文档（00-05）
pi-mono/            # 原始 TypeScript（只读，不要修改）
```

## 编码规则

1. **数据**用 `pub(all) struct`，**联合类型**用 `pub(all) enum`，**行为**用 `pub(open) trait`
2. **开放标识符**用单字段 struct：`pub(all) struct ApiId(String)`
3. **错误处理**用 `Result[T, E]` 和 `suberror`
4. **包名** `snake_case`，**类型** `PascalCase`，**函数** `snake_case`
5. **测试**写在 `*_test.mbt` 的 `test "..."` 块中
6. **包配置**用 `moon.pkg`（非 JSON，是自定义 DSL 格式）
7. **编译目标**：JS 为主要可运行 target，Native/WASM 有 placeholder
8. **不要修改 `pi-mono/` 下的任何文件**

## 提交格式

```
feat(ai): add Message enum and Provider trait
docs(00): project overview and architecture plan
fix(main): correct session path resolution
```
