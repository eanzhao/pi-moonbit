pub let mom_context_file_version : Int = 1

struct MomPersistedContextHeader {
  kind : String
  version : Int
  header : @coding_agent.SessionHeader
  leaf_id : String?
  next_entry_id : Int
} derive(Eq, ToJson, FromJson)

struct MomPersistedContextRecord {
  kind : String
  entry : @coding_agent.SessionEntry
} derive(Eq, ToJson, FromJson)

pub fn load_channel_log_from_workspace(
  runtime : @coding_agent.WorkspaceRuntime,
  workspace_dir : String,
  adapter : String,
  channel_id : String
) -> Result[Array[ChannelMessage], String] {
  let log_path = workspace_channel_log_path(workspace_dir, adapter, channel_id)
  match mom_read_optional_text(runtime, log_path) {
    Ok(Some(text)) => parse_log_jsonl(text, channel_id)
    Ok(None) => Ok([])
    Err(message) => Err(message)
  }
}

pub fn save_channel_log_to_workspace(
  runtime : @coding_agent.WorkspaceRuntime,
  workspace_dir : String,
  adapter : String,
  channel_id : String,
  messages : Array[ChannelMessage]
) -> Result[Unit, String] {
  let log_path = workspace_channel_log_path(workspace_dir, adapter, channel_id)
  (runtime.write_text)(log_path, serialize_log_jsonl(messages))
}

pub fn load_workspace_memory_sections(
  runtime : @coding_agent.WorkspaceRuntime,
  workspace_dir : String,
  adapter : String,
  channel_id : String
) -> Result[(String?, String?), String] {
  let global_memory = match mom_read_optional_text(runtime, workspace_global_memory_path(workspace_dir)) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let channel_memory = match mom_read_optional_text(
    runtime,
    workspace_channel_memory_path(workspace_dir, adapter, channel_id),
  ) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  Ok((global_memory, channel_memory))
}

pub fn load_channel_context_from_workspace(
  runtime : @coding_agent.WorkspaceRuntime,
  workspace_dir : String,
  adapter : String,
  channel_id : String,
  session_id : String,
  timestamp : String
) -> Result[@coding_agent.SessionManager, String] {
  let context_path = workspace_channel_context_path(workspace_dir, adapter, channel_id)
  match mom_read_optional_text(runtime, context_path) {
    Ok(Some(text)) => restore_session_manager_from_context_text(text, context_path)
    Ok(None) => Ok(@coding_agent.SessionManager::new(session_id=session_id, timestamp=timestamp))
    Err(message) => Err(message)
  }
}

pub fn save_channel_context_to_workspace(
  runtime : @coding_agent.WorkspaceRuntime,
  workspace_dir : String,
  adapter : String,
  channel_id : String,
  session_manager : @coding_agent.SessionManager
) -> Result[Unit, String] {
  let context_path = workspace_channel_context_path(workspace_dir, adapter, channel_id)
  let header : MomPersistedContextHeader = {
    kind: "session",
    version: mom_context_file_version,
    header: session_manager.get_header(),
    leaf_id: session_manager.get_leaf_id(),
    next_entry_id: mom_infer_next_entry_id(session_manager.get_entries()),
  }
  let lines : Array[String] = [header.to_json().stringify(escape_slash=false)]
  for entry in session_manager.get_entries() {
    let record : MomPersistedContextRecord = { kind: "entry", entry }
    lines.push(record.to_json().stringify(escape_slash=false))
  }
  (runtime.write_text)(context_path, lines.join("\n") + "\n")
}

fn restore_session_manager_from_context_text(
  text : String,
  context_path : String
) -> Result[@coding_agent.SessionManager, String] {
  let lines = mom_context_non_empty_lines(text)
  if lines.length() == 0 {
    return Err("context file is empty: " + context_path)
  }

  let header_json = match mom_parse_json_line(lines[0], context_path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let header_record : MomPersistedContextHeader = match mom_decode_json(header_json) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if header_record.kind != "session" {
    return Err("invalid context header in " + context_path)
  }
  if header_record.version != mom_context_file_version {
    return Err("unsupported context version in " + context_path)
  }

  let entries : Array[@coding_agent.SessionEntry] = []
  for i in 1..<lines.length() {
    let entry_json = match mom_parse_json_line(lines[i], context_path) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    let entry_record : MomPersistedContextRecord = match mom_decode_json(entry_json) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    if entry_record.kind != "entry" {
      return Err("invalid context entry in " + context_path)
    }
    entries.push(entry_record.entry)
  }

  @coding_agent.SessionManager::restore(
    header_record.header,
    entries,
    leaf_id=header_record.leaf_id,
    next_entry_id=Some(header_record.next_entry_id),
  )
}

fn mom_read_optional_text(
  runtime : @coding_agent.WorkspaceRuntime,
  path : String
) -> Result[String?, String] {
  match (runtime.read_text)(path) {
    Ok(text) => Ok(Some(text))
    Err(message) if mom_is_missing_file_error(message) => Ok(None)
    Err(message) => Err(message)
  }
}

fn mom_is_missing_file_error(message : String) -> Bool {
  let lower = message.to_lower()
  lower.contains("not found") ||
  lower.contains("no such file") ||
  lower.contains("enoent") ||
  lower.contains("cannot find")
}

fn mom_parse_json_line(line : String, context_path : String) -> Result[Json, String] {
  try @json.parse(line) catch {
    _ => Err("failed to parse JSONL record in " + context_path)
  } noraise {
    json => Ok(json)
  }
}

fn[T : FromJson] mom_decode_json(json : Json) -> Result[T, String] {
  try @json.from_json(json) catch {
    error => Err(error.to_string())
  } noraise {
    value => Ok(value)
  }
}

fn mom_context_non_empty_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  for line in text.split("\n") {
    if line.length() > 0 {
      lines.push(line.to_string())
    }
  }
  lines
}

fn mom_infer_next_entry_id(entries : Array[@coding_agent.SessionEntry]) -> Int {
  let mut max_id = 0
  for entry in entries {
    match mom_parse_generated_entry_id(mom_session_entry_id(entry)) {
      Some(value) if value > max_id => max_id = value
      _ => ()
    }
  }
  max_id + 1
}

fn mom_parse_generated_entry_id(id : String) -> Int? {
  if !id.has_prefix("entry-") {
    return None
  }
  let parsed : Result[Int, Error] = try? @string.parse_int(id[6:].to_string())
  match parsed {
    Ok(value) if value > 0 => Some(value)
    _ => None
  }
}

fn mom_session_entry_id(entry : @coding_agent.SessionEntry) -> String {
  match entry {
    @coding_agent.SessionEntry::Message(message_entry) => message_entry.id
    @coding_agent.SessionEntry::ThinkingLevelChange(thinking_entry) => thinking_entry.id
    @coding_agent.SessionEntry::ModelChange(model_entry) => model_entry.id
    @coding_agent.SessionEntry::Compaction(compaction_entry) => compaction_entry.id
    @coding_agent.SessionEntry::BranchSummary(branch_summary_entry) => branch_summary_entry.id
    @coding_agent.SessionEntry::Custom(custom_entry) => custom_entry.id
    @coding_agent.SessionEntry::ContextMessage(context_entry) => context_entry.id
  }
}
