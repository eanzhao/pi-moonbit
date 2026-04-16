# 05 - CLI 入口与集成：src/main

## 这一阶段做了什么？

phase 05 把前四阶段的库真正串成了一个“能跑起来的入口”：

- 新增 `src/main` 包，作为 CLI 主入口
- 加入参数解析：`--print`、`--session`、`--session-dir`、`--continue`、`--resume`、`--no-session`、`--model`、`--provider`、`--api`、`--thinking`
- 把 `lib/coding_agent` 的工具 runtime 接到真实文件系统和 shell
- 加入多 session JSONL 落盘、列举与恢复
- 提供基础 REPL，而不是只做一次性 print 模式
- 给 phase 04 的 session 类型补上 `ToJson/FromJson`，并为 `SessionManager` 增加恢复入口

这意味着仓库现在不只是库集合，而是已经有了一个最小可用的 coding-agent CLI 骨架。

## 这层解决什么问题？

前面几阶段已经有：

1. `lib/ai`：消息、模型、provider 注册
2. `lib/agent`：loop、tool calling、状态与事件
3. `lib/coding_agent`：session、context bridge、工具、扩展 runtime

但还缺最后一层：

1. **命令行入口**：把 argv 变成配置
2. **宿主环境**：把“读文件 / 写文件 / 执行命令 / stdin / stdout”接进来
3. **session 文件**：把内存 session 变成可恢复的 JSONL
4. **session 选择与续跑**：至少要能恢复最近会话或从已保存会话里继续
5. **交互模式**：至少要有一个基础 REPL，能持续发 prompt，而不是只跑单次调用

`src/main` 做的就是这层“把库变成程序”的 glue code。

## 核心结构

```text
src/main/
├── moon.pkg
├── types.mbt          # CLI 配置、host runtime、session file shape
├── args.mbt           # 参数解析与 help 文本
├── session_store.mbt  # JSONL 持久化
├── app.mbt            # 组装 AgentSession、默认工具、print/repl
├── host.mbt           # host runtime 装配
├── host_js.mbt        # Node/JS 下的真实文件/命令/stdin/stdout 实现
├── host_native.mbt    # Native 下的占位 host
├── host_wasm.mbt      # wasm/wasm-gc 下的占位 host
├── main.mbt           # CLI 入口
└── cli_test.mbt       # 参数、session、print/repl 测试
```

`moon.pkg` 里同时声明了 `"is-main": true`，并按 target 选择对应的 host 文件：

- `host_js.mbt` 只用于 `js`
- `host_native.mbt` 只用于 `native` / `llvm`
- `host_wasm.mbt` 只用于 `wasm` / `wasm-gc`

### CliHostRuntime

phase 05 没把平台 API 直接写死到业务逻辑里，而是先抽成 host runtime：

```moonbit
pub(all) struct CliHostRuntime {
  read_text : (String) -> Result[String, String]
  write_text : (String, String) -> Result[Unit, String]
  file_exists : (String) -> Bool
  list_files : (String) -> Result[Array[String], String]
  run_command : (String, String) -> Result[@coding_agent.CommandExecutionResult, String]
  stdout_write : (String) -> Unit
  stderr_write : (String) -> Unit
  read_line : (String) -> String?
  current_dir : () -> String
  now_iso : () -> String
  agent_stream : @agent.AgentStreamFn?
}
```

好处很直接：

- `app.mbt` 不需要知道自己跑在 Node 还是别的宿主里
- 测试可以用纯内存 fake runtime
- session 列举 / resume picker 也能通过统一 runtime 注入
- 之后补 native host 时，不需要重写 CLI 核心

### 参数解析

这一版没有一上来照搬 `pi-mono` 全部 flags，而是先收敛到 phase 05 真正需要的集合：

- `--print`
- `--system-prompt`
- `--session`
- `--session-dir`
- `--continue`
- `--resume`
- `--no-session`
- `--cwd`
- `--model`
- `--provider`
- `--api`
- `--thinking`

以及交互模式下的几个基础命令：

- `:help`
- `:session`
- `:model <id>`
- `:thinking <level>`
- `:quit`

### JSONL session 存储

session 仍然是 JSONL，但这版不再只盯着“单个文件能不能落盘”，而是把 CLI 真正会用到的几种路径都接起来了：

- 默认目录：`.pi-moonbit/sessions/*.jsonl`
- 显式文件：`--session <path>`
- 显式目录：`--session-dir <path>`
- 恢复最近一次：`--continue`
- 从已保存会话中选择：`--resume`

文件格式上，这一版先用一个更简单的 wrapper，而不是直接追求和 `pi-mono` wire-compatible：

- 第一行：`PersistedSessionFileHeader`
- 后续每行：`PersistedSessionRecord`

内部真正持久化的仍然是 `SessionHeader` + `SessionEntry[]`。

为了支持恢复，这一阶段补了两件事：

1. `ai / agent / coding_agent` 里的 session 相关类型加上 `ToJson/FromJson`
2. `SessionManager::restore(...)`，能从持久化 entries 重建内存树、leaf 和 `next_entry_id`

这保持了 phase 04 的运行时设计，只是把它接上了磁盘。

为了支持 `--continue` / `--resume`，`session_store.mbt` 还补了两层操作：

- `list_sessions(...)`：扫描 session 目录并读取轻量信息
- `find_most_recent_session_path(...)`：按时间排序拿最近会话

恢复时还会优先回到 session 文件里记录的 `cwd`，避免“会话恢复了，但工具跑错目录”。

### 默认工具装配

CLI 默认启用四个 phase 04 工具：

- `read`
- `write`
- `edit`
- `bash`

phase 04 里它们已经是 runtime-injected 的；phase 05 只是把它们接到真实 host：

- 文件工具：相对 `cwd` 解析路径，再走 `CliHostRuntime.read_text / write_text`
- `bash`：走 `CliHostRuntime.run_command(command, cwd)`

另外加了一个很小的 `cli-bash-history` 扩展，在 `after_tool_call` 里把 bash 执行记录写回 session context，这样下次继续会话时，模型还能看到最近执行过什么命令。

## 设计决策

### 为什么先做多 target host，但只把 JS 做完整？

当前仓库环境里没有现成的 MoonBit 原生文件/进程运行时依赖，直接硬写 native FFI 风险太高。phase 05 先把 **CLI 核心 + Node host** 落地，native 先返回明确错误，不假装“已经支持”。

同时，为了让 `moon check` / `moon build` 在不同后端上都能过，这一版把 host 按 target 拆开了：`js` 走真实实现，`native` 和 `wasm` 先提供清晰的占位行为与退出路径。

这不是放弃 native，而是先把：

- 参数流
- session 落盘
- print/repl 行为
- 工具 runtime 连接点

这些稳定住。后续只需要替换 `host_native.mbt` 即可。

### 为什么 REPL 不直接复刻 pi-mono 的 interactive TUI？

`pi-mono` 的 interactive mode 很强，但那一层依赖的状态机、组件组合、输入协议要复杂得多。现在先用基础 REPL 把 phase 05 的职责做完整：

- 有 argv 入口
- 有持久化 session
- 有循环交互
- 有最小 in-session control commands

真正的富交互 TUI 可以在后续继续往 `lib/tui` 上叠。

### 为什么 session 格式没有完全对齐 pi-mono？

这一版优先目标是 **把 MoonBit 自己的 session 类型稳定落盘**。如果一开始就完全追 `pi-mono` 的 JSON 字段形状，反而会把 phase 05 的工作重点拖到兼容层。

现在的取舍是：

- 结构思路对齐：header + append-only entries + leaf
- wire format 暂时从简
- 后续如果需要与 `pi-mono` 工具链互通，再做迁移/兼容层

## 测试覆盖

`src/main/cli_test.mbt` 目前覆盖三条主路径：

- 参数解析：print 模式、session path、thinking level
- session store：保存后重新加载，能恢复 transcript / model / thinking，并支持按目录列举最近会话
- CLI 行为：print 模式会输出 assistant 文本并持久化 session；interactive 模式能处理 prompt、`:quit` 和 resume 流程

## 当前状态

phase 05 之后，仓库具备：

- 最小 CLI 主入口
- 真实 host runtime（JS）
- target-aware host 装配（JS / native / wasm）
- 多 session JSONL 存储
- `--continue` 恢复最近会话
- `--resume` 文本选择器恢复指定会话
- 单次 print 模式
- 基础 REPL

但还没有：

- 完整的 `pi-mono` interactive TUI
- session tree navigation / branch picker
- native / wasm host 的真实文件与进程实现
- 多 provider 的真实 CLI 配置与鉴权

也就是说，这一版已经把“库”接成了“程序”，但还不是完整复刻版。
