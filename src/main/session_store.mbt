pub let current_session_file_version : Int = 1

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
