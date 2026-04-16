pub fn InMemorySessionsStore::new() -> InMemorySessionsStore {
  { sessions: [], metadata: [] }
}

pub fn InMemorySessionsStore::save(
  self : InMemorySessionsStore,
  data : SessionData,
  metadata? : SessionMetadata? = None
) -> Unit {
  let resolved_metadata = match metadata {
    Some(value) => value
    None => session_metadata_from_data(data)
  }

  web_ui_store_upsert_session(self.sessions, data)
  web_ui_store_upsert_metadata(self.metadata, resolved_metadata)
}

pub fn InMemorySessionsStore::get(self : InMemorySessionsStore, id : String) -> SessionData? {
  for session in self.sessions {
    if session.id == id {
      return Some(session)
    }
  }
  None
}

pub fn InMemorySessionsStore::get_metadata(
  self : InMemorySessionsStore,
  id : String
) -> SessionMetadata? {
  for metadata in self.metadata {
    if metadata.id == id {
      return Some(metadata)
    }
  }
  None
}

pub fn InMemorySessionsStore::get_all_metadata(self : InMemorySessionsStore) -> Array[SessionMetadata] {
  web_ui_sort_metadata_by_last_modified(self.metadata.copy())
}

pub fn InMemorySessionsStore::delete(self : InMemorySessionsStore, id : String) -> Unit {
  self.sessions = web_ui_filter_sessions(self.sessions, id)
  self.metadata = web_ui_filter_metadata(self.metadata, id)
}

pub fn InMemorySessionsStore::update_title(
  self : InMemorySessionsStore,
  id : String,
  title : String
) -> Unit {
  for i in 0..<self.metadata.length() {
    if self.metadata[i].id == id {
      self.metadata[i] = {
        id: self.metadata[i].id,
        title,
        created_at: self.metadata[i].created_at,
        last_modified: self.metadata[i].last_modified,
        message_count: self.metadata[i].message_count,
        usage: self.metadata[i].usage,
        thinking_level: self.metadata[i].thinking_level,
        preview: self.metadata[i].preview,
      }
    }
  }

  for i in 0..<self.sessions.length() {
    if self.sessions[i].id == id {
      self.sessions[i] = {
        id: self.sessions[i].id,
        title,
        model: self.sessions[i].model,
        thinking_level: self.sessions[i].thinking_level,
        messages: self.sessions[i].messages.copy(),
        created_at: self.sessions[i].created_at,
        last_modified: self.sessions[i].last_modified,
      }
    }
  }
}

pub fn InMemorySessionsStore::get_latest_session_id(self : InMemorySessionsStore) -> String? {
  let all_metadata = self.get_all_metadata()
  if all_metadata.length() == 0 {
    None
  } else {
    Some(all_metadata[0].id)
  }
}

pub fn session_metadata_from_data(data : SessionData) -> SessionMetadata {
  {
    id: data.id,
    title: if data.title.length() > 0 { data.title } else { generate_session_title(data.messages) },
    created_at: data.created_at,
    last_modified: data.last_modified,
    message_count: data.messages.length(),
    usage: session_usage(data.messages),
    thinking_level: data.thinking_level,
    preview: session_preview(data.messages),
  }
}

pub fn generate_session_title(messages : Array[ChatMessage]) -> String {
  for message in messages {
    if web_ui_is_user_message(message) {
      let text = chat_message_text(message, include_assistant=false).trim().to_string()
      if text.length() == 0 {
        continue
      }
      let sentence_end = web_ui_find_sentence_end(text)
      if sentence_end > 0 && sentence_end <= 50 {
        return text[:sentence_end + 1].to_string()
      }
      if text.length() <= 50 {
        return text
      }
      return text[:47].to_string() + "..."
    }
  }
  ""
}

pub fn should_persist_session(messages : Array[ChatMessage]) -> Bool {
  let mut has_user = false
  let mut has_assistant = false
  for message in messages {
    if web_ui_is_user_message(message) {
      has_user = true
    }
    if web_ui_is_assistant_message(message) {
      has_assistant = true
    }
  }
  has_user && has_assistant
}

pub fn session_preview(messages : Array[ChatMessage]) -> String {
  let parts : Array[String] = []
  for message in messages {
    let text = chat_message_text(message)
    if text.length() > 0 {
      parts.push(text)
    }
  }
  web_ui_truncate_text(parts.join("\n"), 2048)
}

pub fn session_usage(messages : Array[ChatMessage]) -> @ai.Usage {
  let mut input = 0
  let mut output = 0
  let mut cache_read = 0
  let mut cache_write = 0
  let mut total_tokens = 0
  let mut input_cost = 0.0
  let mut output_cost = 0.0
  let mut cache_read_cost = 0.0
  let mut cache_write_cost = 0.0
  let mut total_cost = 0.0

  for message in messages {
    match message {
      Standard(@ai.Message::Assistant(assistant_message)) => {
        input = input + assistant_message.usage.input
        output = output + assistant_message.usage.output
        cache_read = cache_read + assistant_message.usage.cache_read
        cache_write = cache_write + assistant_message.usage.cache_write
        total_tokens = total_tokens + assistant_message.usage.total_tokens
        input_cost = input_cost + assistant_message.usage.cost.input
        output_cost = output_cost + assistant_message.usage.cost.output
        cache_read_cost = cache_read_cost + assistant_message.usage.cost.cache_read
        cache_write_cost = cache_write_cost + assistant_message.usage.cost.cache_write
        total_cost = total_cost + assistant_message.usage.cost.total
      }
      _ => ()
    }
  }

  {
    input,
    output,
    cache_read,
    cache_write,
    total_tokens,
    cost: {
      input: input_cost,
      output: output_cost,
      cache_read: cache_read_cost,
      cache_write: cache_write_cost,
      total: total_cost,
    },
  }
}

fn web_ui_store_upsert_session(
  sessions : Array[SessionData],
  data : SessionData
) -> Unit {
  for i in 0..<sessions.length() {
    if sessions[i].id == data.id {
      sessions[i] = data
      return
    }
  }
  sessions.push(data)
}

fn web_ui_store_upsert_metadata(
  metadata_list : Array[SessionMetadata],
  metadata : SessionMetadata
) -> Unit {
  for i in 0..<metadata_list.length() {
    if metadata_list[i].id == metadata.id {
      metadata_list[i] = metadata
      return
    }
  }
  metadata_list.push(metadata)
}

fn web_ui_filter_sessions(sessions : Array[SessionData], id : String) -> Array[SessionData] {
  let retained : Array[SessionData] = []
  for session in sessions {
    if session.id != id {
      retained.push(session)
    }
  }
  retained
}

fn web_ui_filter_metadata(
  metadata_list : Array[SessionMetadata],
  id : String
) -> Array[SessionMetadata] {
  let retained : Array[SessionMetadata] = []
  for metadata in metadata_list {
    if metadata.id != id {
      retained.push(metadata)
    }
  }
  retained
}

fn web_ui_sort_metadata_by_last_modified(
  metadata_list : Array[SessionMetadata]
) -> Array[SessionMetadata] {
  let mut remaining = metadata_list.copy()
  let sorted : Array[SessionMetadata] = []
  while remaining.length() > 0 {
    let latest_index = web_ui_latest_metadata_index(remaining)
    sorted.push(remaining[latest_index])
    remaining = web_ui_filter_metadata_by_index(remaining, latest_index)
  }
  sorted
}

fn web_ui_latest_metadata_index(metadata_list : Array[SessionMetadata]) -> Int {
  let mut latest_index = 0
  for i in 1..<metadata_list.length() {
    if metadata_list[i].last_modified > metadata_list[latest_index].last_modified {
      latest_index = i
    }
  }
  latest_index
}

fn web_ui_filter_metadata_by_index(
  metadata_list : Array[SessionMetadata],
  skipped_index : Int
) -> Array[SessionMetadata] {
  let retained : Array[SessionMetadata] = []
  for i in 0..<metadata_list.length() {
    if i != skipped_index {
      retained.push(metadata_list[i])
    }
  }
  retained
}

fn web_ui_is_user_message(message : ChatMessage) -> Bool {
  match message {
    Standard(@ai.Message::User(_)) => true
    UserWithAttachments(_) => true
    _ => false
  }
}

fn web_ui_is_assistant_message(message : ChatMessage) -> Bool {
  message is Standard(@ai.Message::Assistant(_))
}

fn web_ui_find_sentence_end(text : String) -> Int {
  let mut i = 0
  while i < text.length() {
    let char = text[i:i + 1].to_string()
    if char == "." || char == "!" || char == "?" {
      return i
    }
    i = i + 1
  }
  -1
}

fn web_ui_truncate_text(text : String, limit : Int) -> String {
  if text.length() <= limit {
    text
  } else if limit <= 3 {
    text[:limit].to_string()
  } else {
    text[:limit - 3].to_string() + "..."
  }
}
