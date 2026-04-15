///| 扩展注入到上下文里的自定义消息。
pub(all) struct CustomContextMessage {
  custom_type : String
  content : Array[@ai.ContentBlock]
  display : Bool
  details : Json?
} derive(Eq, ToJson, FromJson)

///| 非 tool 通道的 bash 执行记录。
pub(all) struct BashExecutionMessage {
  command : String
  output : String
  exit_code : Int?
  cancelled : Bool
  truncated : Bool
  full_output_path : String?
} derive(Eq, ToJson, FromJson)

///| 会话头。phase 04 先保留内存态 shape，文件持久化留给 CLI 集成层。
pub(all) struct SessionHeader {
  id : String
  timestamp : String
  parent_session : String?
} derive(Eq, ToJson, FromJson)

///| 标准 transcript 消息 entry。
pub(all) struct SessionMessageEntry {
  id : String
  parent_id : String?
  timestamp : String
  message : @ai.Message
} derive(Eq, ToJson, FromJson)

///| 思维级别切换 entry。
pub(all) struct ThinkingLevelChangeEntry {
  id : String
  parent_id : String?
  timestamp : String
  thinking_level : @agent.AgentThinkingLevel
} derive(Eq, ToJson, FromJson)

///| 模型切换 entry。
pub(all) struct ModelChangeEntry {
  id : String
  parent_id : String?
  timestamp : String
  model : @ai.Model
} derive(Eq, ToJson, FromJson)

///| 对话压缩摘要 entry。
pub(all) struct CompactionEntry {
  id : String
  parent_id : String?
  timestamp : String
  summary : String
  first_kept_entry_id : String
  tokens_before : Int
  details : Json?
  from_hook : Bool
} derive(Eq, ToJson, FromJson)

///| 分支摘要 entry。
pub(all) struct BranchSummaryEntry {
  id : String
  parent_id : String?
  timestamp : String
  from_id : String?
  summary : String
  details : Json?
  from_hook : Bool
} derive(Eq, ToJson, FromJson)

///| 扩展私有状态 entry。
pub(all) struct CustomEntry {
  id : String
  parent_id : String?
  timestamp : String
  custom_type : String
  data : Json?
} derive(Eq, ToJson, FromJson)

///| 参与 LLM context 的上下文消息 entry。
pub(all) struct ContextMessageEntry {
  id : String
  parent_id : String?
  timestamp : String
  message : ContextMessage
} derive(Eq, ToJson, FromJson)

///| coding-agent 扩展出来的上下文消息。
pub(all) enum ContextMessage {
  Custom(CustomContextMessage)
  BashExecution(BashExecutionMessage)
} derive(Eq, ToJson, FromJson)

///| append-only 会话 entry。
pub(all) enum SessionEntry {
  Message(SessionMessageEntry)
  ThinkingLevelChange(ThinkingLevelChangeEntry)
  ModelChange(ModelChangeEntry)
  Compaction(CompactionEntry)
  BranchSummary(BranchSummaryEntry)
  Custom(CustomEntry)
  ContextMessage(ContextMessageEntry)
} derive(Eq, ToJson, FromJson)

///| 解析后的会话上下文。
pub(all) struct SessionContext {
  messages : Array[@ai.Message]
  model : @ai.Model?
  thinking_level : @agent.AgentThinkingLevel?
}

///| 文件工作区操作运行时。
pub(all) struct WorkspaceRuntime {
  read_text : (String) -> Result[String, String]
  write_text : (String, String) -> Result[Unit, String]
}

///| shell 命令执行结果。
pub(all) struct CommandExecutionResult {
  stdout : String
  stderr : String
  exit_code : Int
  cancelled : Bool
  truncated : Bool
  full_output_path : String?
}

///| shell 命令执行运行时。
pub(all) struct CommandRuntime {
  run : (String) -> Result[CommandExecutionResult, String]
}

///| 内存版工作区文件。
pub(all) struct WorkspaceFile {
  path : String
  mut content : String
}

///| 内存版工作区，供 phase 04 的工具测试和 SDK 场景复用。
pub(all) struct InMemoryWorkspace {
  mut files : Array[WorkspaceFile]
}

///| 空的 SessionContext。
pub fn SessionContext::empty() -> SessionContext {
  { messages: [], model: None, thinking_level: None }
}
