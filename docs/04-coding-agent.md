# 04 - Coding Agent 核心：lib/coding_agent

## 这一阶段做了什么？

`lib/coding_agent` 把 phase 03 的 `Agent` 骨架推进成“可编程的 coding session”：

- 提供 append-only 的 `SessionManager`
- 支持标准 transcript 之外的自定义上下文消息
- 提供 `AgentSession`，把 `Agent`、会话上下文和扩展钩子接起来
- 落地最小内置 coding tools：`read`、`write`、`edit`、`bash`
- 提供可注入 runtime，方便先用内存工作区测试，再在 phase 05 接真实 CLI / 文件系统

这意味着 phase 04 完成后，仓库已经不只是“能跑 tool call loop”，而是已经具备一个 **session-aware coding agent core**。

## 这层要解决什么问题？

phase 03 只知道三件事：

1. 发 prompt 给 LLM
2. 执行 `AgentTool`
3. 把结果继续喂回下一轮

但真正的 coding agent 还需要另外三层：

1. **会话树**：消息不是简单数组，而是 append-only session，支持 branch / summary / compaction
2. **扩展消息**：除了 `User / Assistant / ToolResult`，还要能把 branch summary、自定义提示、bash 记录等注入 context
3. **扩展钩子 + 内置工具**：让 coding tools 和 hook runtime 能直接挂进 `Agent`

`lib/coding_agent` 做的就是这层“上下文与能力编排”。

## 核心结构

### SessionEntry

会话不再只有标准消息，而是一棵 entry 树：

```moonbit
enum SessionEntry {
  Message(SessionMessageEntry)
  ThinkingLevelChange(ThinkingLevelChangeEntry)
  ModelChange(ModelChangeEntry)
  Compaction(CompactionEntry)
  BranchSummary(BranchSummaryEntry)
  Custom(CustomEntry)
  ContextMessage(ContextMessageEntry)
}
```

其中：

- `Message`：标准 `@ai.Message`
- `ContextMessage`：会参与 LLM context 的扩展消息
- `Custom`：扩展私有状态，存在 session 里但不进 LLM
- `Compaction / BranchSummary`：把非线性会话压回线性上下文

### ContextMessage

phase 03 暂时没有做 `CustomAgentMessages`。这一阶段的做法是：

```moonbit
enum ContextMessage {
  Custom(CustomContextMessage)
  BashExecution(BashExecutionMessage)
}
```

然后在 `build_session_context()` 时把它们转换成普通 `UserMessage`：

- `Custom`：原样塞回 user content
- `BashExecution`：转成一段文本描述
- `BranchSummary / Compaction`：包上固定 prefix/suffix 后注入

这样不用改 `lib/agent` 的 `Message` 联合类型，也能把扩展消息安全地送进 LLM。

### SessionManager

`SessionManager` 当前实现是内存版 append-only tree：

```moonbit
pub(all) struct SessionManager {
  mut header : SessionHeader
  mut entries : Array[SessionEntry]
  mut leaf_id : String?
  mut next_entry_id : Int
}
```

它提供的关键能力：

- `append_message()`
- `append_custom_message()`
- `append_bash_execution()`
- `append_model_change()`
- `append_thinking_level_change()`
- `append_compaction()`
- `append_branch_summary()`
- `branch()`
- `build_transcript_messages()`
- `build_session_context()`

这里故意把“标准 transcript”和“LLM context”分开：

- `build_transcript_messages()` 只返回真实 `User / Assistant / ToolResult`
- `build_session_context()` 会把 custom message、branch summary、compaction summary 展开成真正送给模型的上下文

这正好对应 pi-mono 里 session manager 和 convert-to-llm 的分层。

### AgentSession

`AgentSession` 是这阶段的主入口：

```moonbit
pub(all) struct AgentSession {
  agent : @agent.Agent
  session_manager : SessionManager
  extensions : ExtensionRuntime
  mut agent_listener : @agent.ListenerHandle?
}
```

它做了四件事：

1. 用 `SessionManager.build_transcript_messages()` 初始化 `Agent.state.messages`
2. 用 `set_transform_context()` 把 LLM 请求上下文切到 `SessionManager.build_session_context()`
3. 监听 `AgentEvent::MessageEnd`，把新增 transcript 自动写回 session
4. 把 extension hooks 接到 `before_tool_call / after_tool_call`

所以 `Agent` 仍然负责 loop，`AgentSession` 负责“让 loop 跑在 session 上”。

## 内置工具

这一版先做最小四件套：

- `create_read_tool(runtime)`
- `create_write_tool(runtime)`
- `create_edit_tool(runtime)`
- `create_bash_tool(runtime)`

但没有直接绑死真实文件系统或 shell，而是走注入 runtime：

```moonbit
struct WorkspaceRuntime {
  read_text : (String) -> Result[String, String]
  write_text : (String, String) -> Result[Unit, String]
}

struct CommandRuntime {
  run : (String) -> Result[CommandExecutionResult, String]
}
```

原因很直接：

1. MoonBit 侧 phase 04 先把 tool protocol 跑通
2. phase 05 的 CLI 再把真实文件系统 / 子进程接进来
3. 测试可以用 `InMemoryWorkspace` 覆盖，不需要依赖外部环境

也就是说，这一阶段已经有 **真实的 coding tool 语义**，但平台依赖故意还没下沉到包里。

## 扩展系统

最初在 `00-project-overview.md` 里预想过直接用 trait。实际落地时，这里先选了和 `AgentTool` 一样的回调结构体：

```moonbit
pub(all) struct CodingExtension {
  name : String
  tools : Array[@agent.AgentTool]
  on_start : ((ExtensionContext) -> Result[Unit, String])?
  before_tool_call : ((@agent.BeforeToolCallContext, ExtensionContext) -> @agent.BeforeToolCallResult?)?
  after_tool_call : ((@agent.AfterToolCallContext, ExtensionContext) -> @agent.AfterToolCallResult?)?
}
```

再由 `ExtensionRuntime` 聚合：

- 启动钩子
- 扩展工具
- `before_tool_call`
- `after_tool_call`

这么做的理由：

1. MoonBit 里 phase 04 先需要“异构扩展列表能直接运行”
2. 回调结构体和 `AgentTool` 的现有风格一致
3. trait object / 注册分发可以等 phase 05+ 再抽象

换句话说，这不是否定 trait，而是优先把运行时闭环做稳。

## 文件结构

```text
lib/coding_agent/
├── moon.pkg
├── types.mbt
├── messages.mbt
├── session_manager.mbt
├── tools.mbt
├── extensions.mbt
├── session.mbt
├── session_manager_test.mbt
├── tools_test.mbt
└── session_test.mbt
```

## 测试覆盖

本阶段新增 7 个测试，覆盖三类风险：

- `session_manager_test.mbt`
  - branch summary + custom message 进入上下文
  - compaction summary 只保留 kept messages
  - model / thinking level 能从 session 还原
- `tools_test.mbt`
  - `write` + `read` 通过内存工作区互通
  - `edit` 只替换首个匹配块
  - `bash` 非零退出码走错误路径
- `session_test.mbt`
  - `AgentSession` 会持久化 transcript，并把 custom context 注入 LLM 请求
  - extension `before_tool_call` 能阻止工具执行

## 和 pi-mono 的差异

| pi-mono | 当前实现 |
|---|---|
| JSONL 持久化 session 文件 | phase 04 先做内存态 `SessionManager` |
| 完整 interactive / print / rpc runtime | 留到 phase 05 CLI 集成 |
| 动态扩展加载 | 先做静态注册的 `ExtensionRuntime` |
| 真实文件系统 / shell 工具实现 | 先做 runtime 注入，测试用内存版 |
| compaction 策略本身 | 本阶段只支持 compaction entry 的上下文重建 |

## 当前状态

phase 04 的“核心层”已经具备：

- 会话树和 branch/summary 语义
- 非标准消息到 LLM context 的桥接
- 可注入的 coding tools
- 扩展钩子运行时
- 高层 `AgentSession`

下一步 phase 05 就是把这些核心能力接进 `src/main`：

- 真实文件系统 / shell runtime
- CLI 命令入口
- session 文件落盘
- 终端交互层
