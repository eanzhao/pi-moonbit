pub let current_session_file_version : Int = 1

pub fn default_session_dir(cwd : String) -> String {
  let home = host_env_var("HOME").unwrap_or(cwd)
  if home.has_suffix("/") {
    home + ".pimbt/sessions"
  } else {
    home + "/.pimbt/sessions"
  }
}

pub fn session_file_path(session_dir : String, session_id : String) -> String {
  let filename = session_id + ".jsonl"
  if session_dir.has_suffix("/") {
    session_dir + filename
  } else {
    session_dir + "/" + filename
  }
}

pub fn load_session_from_file(
  runtime : CliHostRuntime,
  session_path : String
) -> Result[LoadedSession, String] {
  match (runtime.read_text)(session_path) {
    Err(message) => Err(message)
    Ok(text) => {
      let lines = non_empty_lines(text)
      if lines.length() == 0 {
        return Err("session file is empty: " + session_path)
      }

      let header_json = match parse_json_line(lines[0], session_path) {
        Ok(json) => json
        Err(message) => return Err(message)
      }
      let header_record : PersistedSessionFileHeader = match decode_json(header_json) {
        Ok(record) => record
        Err(message) => return Err(message)
      }
      if header_record.kind != "session" {
        return Err("invalid session header in " + session_path)
      }

      let entries : Array[@coding_agent.SessionEntry] = []
      for i in 1..<lines.length() {
        let entry_json = match parse_json_line(lines[i], session_path) {
          Ok(json) => json
          Err(message) => return Err(message)
        }
        let entry_record : PersistedSessionRecord = match decode_json(entry_json) {
          Ok(record) => record
          Err(message) => return Err(message)
        }
        if entry_record.kind != "entry" {
          return Err("invalid session entry in " + session_path)
        }
        entries.push(entry_record.entry)
      }

      match @coding_agent.SessionManager::restore(
        header_record.header,
        entries,
        leaf_id=header_record.leaf_id,
        next_entry_id=Some(header_record.next_entry_id),
      ) {
        Ok(session_manager) => Ok({ cwd: header_record.cwd, session_manager })
        Err(message) => Err(message)
      }
    }
  }
}

pub fn load_session_info(
  runtime : CliHostRuntime,
  session_path : String
) -> Result[SessionInfo, String] {
  match load_session_from_file(runtime, session_path) {
    Err(message) => Err(message)
    Ok(loaded) => {
      let header = loaded.session_manager.get_header()
      let transcript = loaded.session_manager.build_transcript_messages()
      Ok({
        path: session_path,
        session_id: header.id,
        cwd: loaded.cwd,
        timestamp: header.timestamp,
        parent_session: header.parent_session,
        leaf_id: loaded.session_manager.get_leaf_id(),
        entry_count: loaded.session_manager.get_entries().length(),
        preview: session_preview(transcript),
      })
    }
  }
}

pub fn list_sessions(
  runtime : CliHostRuntime,
  session_dir : String
) -> Result[Array[SessionInfo], String] {
  let files = match (runtime.list_files)(session_dir) {
    Ok(paths) => paths
    Err(message) => return Err(message)
  }
  let sessions : Array[SessionInfo] = []
  for path in files {
    if path.has_suffix(".jsonl") {
      match load_session_info(runtime, path) {
        Ok(info) => sessions.push(info)
        Err(message) => return Err(message)
      }
    }
  }
  Ok(sort_sessions_by_recency(sessions))
}

pub fn find_most_recent_session_path(
  runtime : CliHostRuntime,
  session_dir : String
) -> Result[String?, String] {
  match list_sessions(runtime, session_dir) {
    Err(message) => Err(message)
    Ok(sessions) =>
      if sessions.length() == 0 {
        Ok(None)
      } else {
        Ok(Some(sessions[0].path))
      }
  }
}

pub fn save_session_to_file(
  runtime : CliHostRuntime,
  session_manager : @coding_agent.SessionManager,
  session_path : String,
  cwd : String
) -> Result[Unit, String] {
  let header : PersistedSessionFileHeader = {
    kind: "session",
    version: current_session_file_version,
    header: session_manager.get_header(),
    cwd,
    leaf_id: session_manager.get_leaf_id(),
    next_entry_id: infer_next_entry_id(session_manager.get_entries()),
  }

  let lines : Array[String] = [header.to_json().stringify(escape_slash=false)]
  for entry in session_manager.get_entries() {
    let record : PersistedSessionRecord = { kind: "entry", entry }
    lines.push(record.to_json().stringify(escape_slash=false))
  }
  (runtime.write_text)(session_path, lines.join("\n") + "\n")
}

fn parse_json_line(line : String, session_path : String) -> Result[Json, String] {
  try @json.parse(line) catch {
    _ => Err("failed to parse JSONL record in " + session_path)
  } noraise {
    json => Ok(json)
  }
}

fn[T : FromJson] decode_json(json : Json) -> Result[T, String] {
  try @json.from_json(json) catch {
    error => Err(error.to_string())
  } noraise {
    value => Ok(value)
  }
}

fn non_empty_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  for line in text.split("\n") {
    if line.length() > 0 {
      lines.push(line.to_string())
    }
  }
  lines
}

fn infer_next_entry_id(entries : Array[@coding_agent.SessionEntry]) -> Int {
  let mut max_id = 0
  for entry in entries {
    match parse_generated_entry_id(session_entry_id(entry)) {
      Some(value) if value > max_id => max_id = value
      _ => ()
    }
  }
  max_id + 1
}

fn sort_sessions_by_recency(sessions : Array[SessionInfo]) -> Array[SessionInfo] {
  let mut remaining = sessions.copy()
  let sorted : Array[SessionInfo] = []
  while remaining.length() > 0 {
    let latest_index = latest_session_index(remaining)
    sorted.push(remaining[latest_index])

    let next_remaining : Array[SessionInfo] = []
    for i in 0..<remaining.length() {
      if i != latest_index {
        next_remaining.push(remaining[i])
      }
    }
    remaining = next_remaining
  }
  sorted
}

fn latest_session_index(sessions : Array[SessionInfo]) -> Int {
  let mut latest_index = 0
  for i in 1..<sessions.length() {
    if session_recency_key(sessions[i]) > session_recency_key(sessions[latest_index]) {
      latest_index = i
    }
  }
  latest_index
}

fn session_recency_key(info : SessionInfo) -> String {
  if info.timestamp.length() > 0 {
    info.timestamp
  } else {
    info.session_id
  }
}

fn session_preview(messages : Array[@ai.Message]) -> String {
  let user_preview = latest_message_preview(messages, true)
  if user_preview.length() > 0 {
    return user_preview
  }
  latest_message_preview(messages, false)
}

fn latest_message_preview(
  messages : Array[@ai.Message],
  user_only : Bool
) -> String {
  let mut i = messages.length()
  while i > 0 {
    i = i - 1
    match message_preview(messages[i], user_only) {
      Some(text) if text.length() > 0 => return truncate_preview(text)
      _ => ()
    }
  }
  ""
}

fn message_preview(message : @ai.Message, user_only : Bool) -> String? {
  match message {
    @ai.Message::User(user) => {
      let text = content_preview(user.content)
      if text.length() > 0 { Some(text) } else { None }
    }
    @ai.Message::Assistant(assistant) =>
      if user_only {
        None
      } else {
        let text = content_preview(assistant.content)
        if text.length() > 0 { Some(text) } else { None }
      }
    @ai.Message::ToolResult(_) => None
  }
}

fn content_preview(content : Array[@ai.ContentBlock]) -> String {
  let parts : Array[String] = []
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) => {
        let normalized = normalize_preview_text(text)
        if normalized.length() > 0 {
          parts.push(normalized)
        }
      }
      _ => ()
    }
  }
  parts.join(" ")
}

fn normalize_preview_text(text : String) -> String {
  text
    .replace_all(old="\n", new=" ")
    .replace_all(old="\r", new=" ")
    .trim()
    .to_string()
}

fn truncate_preview(text : String) -> String {
  if text.length() <= 72 {
    text
  } else {
    text[:69].to_string() + "..."
  }
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

fn session_entry_id(entry : @coding_agent.SessionEntry) -> String {
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
