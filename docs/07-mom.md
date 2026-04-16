# 07 - Mom 运行层：lib/mom

## 这一阶段做了什么？

phase 07 没有直接把 `pi-mono/packages/mom` 的 Slack Socket Mode 和 Docker 执行器原样搬过来，而是先把 MoonBit 最适合承接、也最容易测试的那层平台无关运行层落成了一个新的 `lib/mom` 包：

- 统一 channel / user / attachment / message 数据模型
- 平台无关的 workspace 路径规划与 channel namespace 规则
- `log.jsonl` 的 JSONL 解析与序列化
- channel log 到 `SessionManager` 的 context 同步逻辑
- sandbox 参数解析与 host/container 路径映射
- events JSON 解析、序列化与触发消息格式化
- mom system prompt 生成与 skill 列表格式化
- 一个纯内存的 `InMemoryChannelStore`
- `MomAgentRuntime` / `MomAgentConfig` 运行时装配
- `MomAgent`：按 `adapter/channel` 复用 `AgentSession`
- channel 消息驱动 `coding_agent.AgentSession` 执行，并把 assistant 回复回写到 log
- `@agent.AgentEvent` 透传与运行状态跟踪
- `workspace.mbt`：`log.jsonl` / `context.jsonl` / `MEMORY.md` 的工作区读写与恢复

对应源码：

```text
lib/mom/
├── moon.pkg
├── types.mbt
├── store.mbt
├── context.mbt
├── sandbox.mbt
├── events.mbt
├── prompt.mbt
├── agent.mbt
├── workspace.mbt
├── store_test.mbt
├── context_test.mbt
├── sandbox_test.mbt
├── events_test.mbt
├── prompt_test.mbt
└── agent_test.mbt
```

这意味着仓库现在已经有了 mom 的“平台无关运行层”，而不再只是 README 里的一个待开发占位包。

## 为什么不先硬接 Slack？

`pi-mono` 当前 `mom` 的运行时高度依赖宿主：

- Slack Socket Mode / Web API
- Docker / host shell
- 文件下载
- 定时器与 cron

这些部分在 MoonBit 里如果一开始就直接做，会立刻把工作重心拖到第三方绑定和平台细节上。对这个仓库来说，更合理的顺序是先把稳定抽象讲清楚：

1. channel 消息长什么样
2. workspace 目录怎么命名
3. `log.jsonl` 如何映射回 `coding_agent` 的 `SessionManager`
4. event 文件的 shape 是什么
5. sandbox 配置如何影响 prompt 和路径翻译

这一步做完，后续无论是接 Slack、Discord，还是做 CLI/mock adapter，都会变成“接线”而不是“重新设计 mom”。

## 采用哪条架构路线？

这里没有照抄 `src/slack.ts -> agent.ts -> SlackContext` 那条 Slack-specific 结构，而是优先采用 `pi-mono/packages/mom/docs/new.md` 里提出的多平台方向：

- channel 用统一 `ChannelMessage`
- channel workspace 走 `channels/<adapter>/<channelId>/`
- events 用限定名 channel id：`adapter/channel`
- prompt 输出标准 markdown，由 adapter 自己做平台格式转换

MoonBit 版当前实现的核心类型大致是：

```moonbit
pub(all) struct ChannelMessage {
  id : String
  channel_id : String
  timestamp : String
  sender : ChannelSender
  text : String
  attachments : Array[ChannelAttachment]
  is_mention : Bool
  reply_to : String?
  metadata : Json?
}
```

以及：

```moonbit
pub(all) enum MomEvent {
  Immediate(ImmediateEvent)
  OneShot(OneShotEvent)
  Periodic(PeriodicEvent)
}
```

这两类数据基本把 mom 最核心的外部输入稳定住了。

## 这层怎么接已有 coding-agent？

这阶段最关键的桥接点有两处。

第一处是 `context.mbt`：

- `channel_message_to_context_text(...)` 把 channel 消息转成标准 user text
- `channel_message_to_user_message(...)` 把它映射为 `@ai.UserMessage`
- `sync_channel_log_to_session_manager(...)` 把未同步的非 bot 消息补进 `SessionManager`

这样 mom 不需要自己重新发明一套上下文树；它直接复用 phase 04 已经实现好的 append-only session 和 context build 逻辑。

第二处是 `agent.mbt`：

- `MomAgentRuntime` 组合 `WorkspaceRuntime`、`CommandRuntime` 和可注入 `stream_fn`
- `MomAgentConfig` 统一 model、sandbox、memory、tool/extension 装配
- `MomAgent` 为每个 `adapter/channel` 建一个 `MomChannelSession`
- `handle_message(...)` 会把当前 channel 的历史 log 同步进 `SessionManager`
- 然后重建 system prompt，调用 `AgentSession.prompt_message(...)`
- 运行完成后把最新 assistant 文本回写进 `channel_store`
- 并把 `log.jsonl` / `context.jsonl` 保存回工作区

这让 mom 已经不只是“能准备 prompt”，而是能真正接住一条 channel 消息并驱动底层 coding agent 跑完一个 turn。

第三处是 `workspace.mbt`：

- `load_channel_log_from_workspace(...)` / `save_channel_log_to_workspace(...)`
- `load_channel_context_from_workspace(...)` / `save_channel_context_to_workspace(...)`
- `load_workspace_memory_sections(...)`

也就是说，channel session 现在不再只是进程内状态；它已经可以从工作区恢复 `context.jsonl`，并在每次 turn 结束后把上下文重新写回工作区。

另外，memory 也先做成纯文本组合函数：

- workspace memory
- channel memory

统一拼成 prompt 所需的 working memory 片段。

## `store.mbt` 负责什么？

这一版的 store 没去碰真实文件系统 API，而是先做三件稳定的事：

1. **路径规则**
   - `workspace/events/`
   - `workspace/channels/<adapter>/<channelId>/log.jsonl`
   - `attachments/`、`scratch/`、`skills/`
2. **JSONL 编解码**
   - 能写出 MoonBit 版统一消息格式
   - 能读回更旧的 Slack-specific log shape（如 `user/userName/displayName/original/local`）
3. **内存 store**
   - 追加消息
   - 按 channel 取 log
   - 生成 preview / message_count / last_message_at

这让 phase 07 保持纯函数和可测试，不需要先把宿主 runtime 抽象再做一遍。

在这之上，`MomAgent` 再把内存 store 当作最小可运行宿主，用它来验证：

1. 每个 channel 只初始化一次 session
2. 历史用户消息会被同步到 `SessionManager`
3. 当前 prompt 跑完后，assistant 回复会进入 channel log

## prompt 为什么改成标准 markdown？

`pi-mono` 的现有 Slack 版 system prompt 里有大量 mrkdwn 细节，比如：

- `*bold*`
- `<url|text>`
- `<@user>`

但这会把 agent 直接绑死到 Slack 上。MoonBit 版这里改成平台无关 prompt：

- agent 只输出标准 markdown
- mentions 用 `@username`
- 真正发到 Slack/Discord 时，再由 adapter 做格式转换

这和 `new.md` 的方向一致，也更适合后续扩展到多个聊天平台。

## 测试覆盖

`lib/mom` 当前新增 16 个测试，覆盖六条主线：

### store_test.mbt

- workspace 路径按 adapter/channel 命名
- `log.jsonl` 能 round-trip
- 能兼容旧的 Slack log shape
- 内存 store 去重并按最近消息排序 metadata

### context_test.mbt

- memory 文本能合并 workspace / channel 两层内容
- channel message 会把附件路径编码进上下文文本
- log sync 会跳过 bot / 当前消息，并按时间顺序追加

### sandbox / events / prompt tests

- `host` / `docker:<name>` 解析正确
- host 路径能翻译到 `/workspace/...`
- event JSON 能解析并生成 `[EVENT:...]` 触发文本
- system prompt 包含 memory、skills、events 与平台无关格式说明

### agent_test.mbt

- `handle_message(...)` 会创建 session、透传 agent events，并写回 bot log
- 历史 channel log 会在当前 prompt 前同步进 `SessionManager`
- `is_running(...)` 会在回调期间为真，执行结束后恢复为假
- 新实例可以从 `context.jsonl` 恢复已有 session transcript
- `MEMORY.md` 会自动读入 system prompt

## 当前状态

phase 07 之后，`lib/mom` 已经具备：

- 平台无关消息模型
- per-channel `AgentSession` 运行层
- workspace/channel namespace 规则
- log JSONL 编解码
- workspace-backed `log.jsonl` / `context.jsonl` 持久化
- context sync 到 `SessionManager`
- sandbox 参数与路径映射
- events 解析与 prompt 支撑
- mom system prompt 生成

但还没有直接进入 MoonBit 仓库的部分仍然是宿主绑定：

- Slack / Discord adapter
- 实时 socket 连接
- 真实文件下载
- cron / watcher 调度器
- 真实 bash executor 和容器校验

也就是说，这一版完成的是 mom 的“平台无关运行层”，而不是最终可联网运行的聊天机器人宿主。
