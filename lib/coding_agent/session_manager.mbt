///| append-only 的会话管理器。phase 04 先做内存树结构和上下文重建。
pub(all) struct SessionManager {
  mut header : SessionHeader
  mut entries : Array[SessionEntry]
  mut leaf_id : String?
  mut next_entry_id : Int
}

///| 创建一个新的内存会话。
pub fn SessionManager::new(
  session_id? : String = "session-1",
  timestamp? : String = "",
  parent_session? : String? = None
) -> SessionManager {
  {
    header: { id: session_id, timestamp, parent_session },
    entries: [],
    leaf_id: None,
    next_entry_id: 1,
  }
}

///| 从已持久化的 header + entries 恢复 SessionManager。
pub fn SessionManager::restore(
  header : SessionHeader,
  entries : Array[SessionEntry],
  leaf_id? : String? = None,
  next_entry_id? : Int? = None
) -> Result[SessionManager, String] {
  for entry in entries {
    match entry_parent_id(entry) {
      Some(parent_id) =>
        if find_session_entry(entries, parent_id) is None {
          return Err("entry \{entry_id(entry)} has unknown parent \{parent_id}")
        }
      None => ()
    }
  }

  let restored_leaf_id = match leaf_id {
    Some(id) =>
      match find_session_entry(entries, id) {
        Some(_) => Some(id)
        None => return Err("leaf entry \{id} not found")
      }
    None => default_leaf_id(entries)
  }

  let restored_next_entry_id = match next_entry_id {
    Some(value) if value > 0 => value
    _ => infer_next_entry_id(entries)
  }

  Ok({
    header,
    entries: entries.copy(),
    leaf_id: restored_leaf_id,
    next_entry_id: restored_next_entry_id,
  })
}

///| 获取会话头。
pub fn SessionManager::get_header(self : SessionManager) -> SessionHeader {
  self.header
}

///| 获取当前 leaf id。
pub fn SessionManager::get_leaf_id(self : SessionManager) -> String? {
  self.leaf_id
}

///| 获取全部 entry 的拷贝。
pub fn SessionManager::get_entries(self : SessionManager) -> Array[SessionEntry] {
  self.entries.copy()
}

///| 按 id 查找 entry。
pub fn SessionManager::get_entry(self : SessionManager, entry_id : String) -> SessionEntry? {
  find_session_entry(self.entries, entry_id)
}

///| 从指定节点切换到另一条分支。传 `None` 表示回到根前。
pub fn SessionManager::branch(self : SessionManager, entry_id : String?) -> Result[Unit, String] {
  match entry_id {
    None => {
      self.leaf_id = None
      Ok(())
    }
    Some(id) =>
      match self.get_entry(id) {
        Some(_) => {
          self.leaf_id = Some(id)
          Ok(())
        }
        None => Err("entry \{id} not found")
      }
  }
}

///| 获取从 root 到当前 leaf 的 entry 路径。
pub fn SessionManager::get_branch(self : SessionManager, from_id? : String? = self.leaf_id) -> Array[SessionEntry] {
  let reversed : Array[SessionEntry] = []
  let mut current_id = from_id
  while true {
    match current_id {
      None => break
      Some(id) =>
        match self.get_entry(id) {
          Some(entry) => {
            reversed.push(entry)
            current_id = entry_parent_id(entry)
          }
          None => break
        }
    }
  }
  reverse_entries(reversed)
}

///| 仅返回标准 transcript 消息，不混入 compaction / custom context。
pub fn SessionManager::build_transcript_messages(self : SessionManager) -> Array[@ai.Message] {
  let messages : Array[@ai.Message] = []
  for entry in self.get_branch() {
    match entry {
      Message(message_entry) => messages.push(message_entry.message)
      _ => ()
    }
  }
  messages
}

///| 构建送给 LLM 的上下文快照。
pub fn SessionManager::build_session_context(self : SessionManager) -> SessionContext {
  let path = self.get_branch()
  if path.length() == 0 {
    return SessionContext::empty()
  }

  let mut model : @ai.Model? = None
  let mut thinking_level : @agent.AgentThinkingLevel? = None
  let mut latest_compaction : CompactionEntry? = None

  for entry in path {
    match entry {
      ModelChange(model_entry) => model = Some(model_entry.model)
      ThinkingLevelChange(thinking_entry) => thinking_level = Some(thinking_entry.thinking_level)
      Compaction(compaction_entry) => latest_compaction = Some(compaction_entry)
      _ => ()
    }
  }

  let messages : Array[@ai.Message] = []
  match latest_compaction {
    Some(compaction_entry) => {
      messages.push(compaction_entry_to_llm(compaction_entry))

      let compaction_index = find_path_index(path, compaction_entry.id)
      let mut found_first_kept = false
      for i in 0..<compaction_index {
        let entry = path[i]
        if entry_id(entry) == compaction_entry.first_kept_entry_id {
          found_first_kept = true
        }
        if found_first_kept {
          append_context_message(messages, entry)
        }
      }
      let mut i = compaction_index + 1
      while i < path.length() {
        append_context_message(messages, path[i])
        i = i + 1
      }
    }
    None =>
      for entry in path {
        append_context_message(messages, entry)
      }
  }

  { messages, model, thinking_level }
}

///| 追加标准消息 entry。
pub fn SessionManager::append_message(self : SessionManager, message : @ai.Message, timestamp? : String = "") -> String {
  let entry_id = self.next_id()
  let entry = Message({
    id: entry_id,
    parent_id: self.leaf_id,
    timestamp,
    message,
  })
  self.append_entry(entry)
}

///| 追加模型切换 entry。
pub fn SessionManager::append_model_change(
  self : SessionManager,
  model : @ai.Model,
  timestamp? : String = ""
) -> String {
  let entry_id = self.next_id()
  let entry = ModelChange({
    id: entry_id,
    parent_id: self.leaf_id,
    timestamp,
    model,
  })
  self.append_entry(entry)
}

///| 追加思维级别切换 entry。
pub fn SessionManager::append_thinking_level_change(
  self : SessionManager,
  thinking_level : @agent.AgentThinkingLevel,
  timestamp? : String = ""
) -> String {
  let entry_id = self.next_id()
  let entry = ThinkingLevelChange({
    id: entry_id,
    parent_id: self.leaf_id,
    timestamp,
    thinking_level,
  })
  self.append_entry(entry)
}

///| 追加扩展私有状态 entry。
pub fn SessionManager::append_custom_entry(
  self : SessionManager,
  custom_type : String,
  data? : Json? = None,
  timestamp? : String = ""
) -> String {
  let entry_id = self.next_id()
  let entry = SessionEntry::Custom({
    id: entry_id,
    parent_id: self.leaf_id,
    timestamp,
    custom_type,
    data,
  })
  self.append_entry(entry)
}

///| 追加参与 LLM context 的自定义消息 entry。
pub fn SessionManager::append_custom_message(
  self : SessionManager,
  custom_type : String,
  content : Array[@ai.ContentBlock],
  display? : Bool = true,
  details? : Json? = None,
  timestamp? : String = ""
) -> String {
  self.append_context_message(
    ContextMessage::Custom({ custom_type, content: content.copy(), display, details }),
    timestamp~,
  )
}

///| 追加 bash 执行记录 entry。
pub fn SessionManager::append_bash_execution(
  self : SessionManager,
  command : String,
  output : String,
  exit_code? : Int? = None,
  cancelled? : Bool = false,
  truncated? : Bool = false,
  full_output_path? : String? = None,
  timestamp? : String = ""
) -> String {
  self.append_context_message(
    ContextMessage::BashExecution({
      command,
      output,
      exit_code,
      cancelled,
      truncated,
      full_output_path,
    }),
    timestamp~,
  )
}

///| 追加 compaction 摘要 entry。
pub fn SessionManager::append_compaction(
  self : SessionManager,
  summary : String,
  first_kept_entry_id : String,
  tokens_before : Int,
  details? : Json? = None,
  from_hook? : Bool = false,
  timestamp? : String = ""
) -> String {
  let entry_id = self.next_id()
  let entry = Compaction({
    id: entry_id,
    parent_id: self.leaf_id,
    timestamp,
    summary,
    first_kept_entry_id,
    tokens_before,
    details,
    from_hook,
  })
  self.append_entry(entry)
}

///| 追加 branch summary entry。
pub fn SessionManager::append_branch_summary(
  self : SessionManager,
  summary : String,
  from_id? : String? = None,
  details? : Json? = None,
  from_hook? : Bool = false,
  timestamp? : String = ""
) -> String {
  let entry_id = self.next_id()
  let entry = BranchSummary({
    id: entry_id,
    parent_id: self.leaf_id,
    timestamp,
    from_id,
    summary,
    details,
    from_hook,
  })
  self.append_entry(entry)
}

fn SessionManager::append_context_message(
  self : SessionManager,
  message : ContextMessage,
  timestamp? : String = ""
) -> String {
  let entry_id = self.next_id()
  let entry = ContextMessage({
    id: entry_id,
    parent_id: self.leaf_id,
    timestamp,
    message,
  })
  self.append_entry(entry)
}

fn SessionManager::next_id(self : SessionManager) -> String {
  let entry_id = "entry-\{self.next_entry_id}"
  self.next_entry_id = self.next_entry_id + 1
  entry_id
}

fn SessionManager::append_entry(self : SessionManager, entry : SessionEntry) -> String {
  let id = entry_id(entry)
  self.entries.push(entry)
  self.leaf_id = Some(id)
  id
}

fn append_context_message(messages : Array[@ai.Message], entry : SessionEntry) -> Unit {
  match entry {
    Message(message_entry) => messages.push(message_entry.message)
    ContextMessage(context_entry) => messages.push(context_message_to_llm(context_entry.message))
    BranchSummary(branch_summary_entry) => messages.push(branch_summary_entry_to_llm(branch_summary_entry))
    _ => ()
  }
}

fn find_session_entry(entries : Array[SessionEntry], target_id : String) -> SessionEntry? {
  for entry in entries {
    if entry_id(entry) == target_id {
      return Some(entry)
    }
  }
  None
}

fn entry_id(entry : SessionEntry) -> String {
  match entry {
    Message(message_entry) => message_entry.id
    ThinkingLevelChange(thinking_entry) => thinking_entry.id
    ModelChange(model_entry) => model_entry.id
    Compaction(compaction_entry) => compaction_entry.id
    BranchSummary(branch_summary_entry) => branch_summary_entry.id
    Custom(custom_entry) => custom_entry.id
    ContextMessage(context_entry) => context_entry.id
  }
}

fn entry_parent_id(entry : SessionEntry) -> String? {
  match entry {
    Message(message_entry) => message_entry.parent_id
    ThinkingLevelChange(thinking_entry) => thinking_entry.parent_id
    ModelChange(model_entry) => model_entry.parent_id
    Compaction(compaction_entry) => compaction_entry.parent_id
    BranchSummary(branch_summary_entry) => branch_summary_entry.parent_id
    Custom(custom_entry) => custom_entry.parent_id
    ContextMessage(context_entry) => context_entry.parent_id
  }
}

fn find_path_index(path : Array[SessionEntry], target_id : String) -> Int {
  for i in 0..<path.length() {
    if entry_id(path[i]) == target_id {
      return i
    }
  }
  path.length()
}

fn reverse_entries(entries : Array[SessionEntry]) -> Array[SessionEntry] {
  let reversed : Array[SessionEntry] = []
  for i in 0..<entries.length() {
    reversed.push(entries[entries.length() - 1 - i])
  }
  reversed
}

fn default_leaf_id(entries : Array[SessionEntry]) -> String? {
  if entries.length() == 0 {
    return None
  }
  Some(entry_id(entries[entries.length() - 1]))
}

fn infer_next_entry_id(entries : Array[SessionEntry]) -> Int {
  let mut max_id = 0
  for entry in entries {
    match parse_generated_entry_id(entry_id(entry)) {
      Some(value) if value > max_id => max_id = value
      _ => ()
    }
  }
  max_id + 1
}

fn parse_generated_entry_id(id : String) -> Int? {
  if !id.has_prefix("entry-") {
    return None
  }
  let parsed : Result[Int, Error] = try? @string.parse_int(id[6:].to_string())
  match parsed {
    Ok(value) if value > 0 => Some(value)
    _ => None
  }
}
