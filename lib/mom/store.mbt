pub fn workspace_global_memory_path(workspace_dir : String) -> String {
  mom_join_path(workspace_dir, "MEMORY.md")
}

pub fn workspace_skills_dir(workspace_dir : String) -> String {
  mom_join_path(workspace_dir, "skills")
}

pub fn workspace_events_dir(workspace_dir : String) -> String {
  mom_join_path(workspace_dir, "events")
}

pub fn workspace_event_file_path(
  workspace_dir : String,
  filename : String
) -> String {
  mom_join_path(workspace_events_dir(workspace_dir), filename)
}

pub fn event_filename_in_dir(
  events_dir : String,
  path : String
) -> String? {
  if !path.contains("/") {
    return if path.length() > 0 { Some(path) } else { None }
  }
  let prefix = if events_dir.has_suffix("/") { events_dir } else { events_dir + "/" }
  if !path.has_prefix(prefix) {
    return None
  }
  let filename = path[prefix.length():].to_string()
  if filename.length() > 0 {
    Some(filename)
  } else {
    None
  }
}

pub fn workspace_event_filename(
  workspace_dir : String,
  path : String
) -> String? {
  event_filename_in_dir(workspace_events_dir(workspace_dir), path)
}

pub fn workspace_channels_dir(workspace_dir : String) -> String {
  mom_join_path(workspace_dir, "channels")
}

pub fn workspace_channel_dir(
  workspace_dir : String,
  adapter : String,
  channel_id : String
) -> String {
  mom_join_path(mom_join_path(workspace_channels_dir(workspace_dir), adapter), channel_id)
}

pub fn workspace_channel_memory_path(
  workspace_dir : String,
  adapter : String,
  channel_id : String
) -> String {
  mom_join_path(workspace_channel_dir(workspace_dir, adapter, channel_id), "MEMORY.md")
}

pub fn workspace_channel_log_path(
  workspace_dir : String,
  adapter : String,
  channel_id : String
) -> String {
  mom_join_path(workspace_channel_dir(workspace_dir, adapter, channel_id), "log.jsonl")
}

pub fn workspace_channel_context_path(
  workspace_dir : String,
  adapter : String,
  channel_id : String
) -> String {
  mom_join_path(workspace_channel_dir(workspace_dir, adapter, channel_id), "context.jsonl")
}

pub fn workspace_channel_attachments_dir(
  workspace_dir : String,
  adapter : String,
  channel_id : String
) -> String {
  mom_join_path(workspace_channel_dir(workspace_dir, adapter, channel_id), "attachments")
}

pub fn workspace_channel_scratch_dir(
  workspace_dir : String,
  adapter : String,
  channel_id : String
) -> String {
  mom_join_path(workspace_channel_dir(workspace_dir, adapter, channel_id), "scratch")
}

pub fn workspace_channel_skills_dir(
  workspace_dir : String,
  adapter : String,
  channel_id : String
) -> String {
  mom_join_path(workspace_channel_dir(workspace_dir, adapter, channel_id), "skills")
}

pub fn qualified_channel_id(adapter : String, channel_id : String) -> String {
  adapter + "/" + channel_id
}

pub fn parse_qualified_channel_id(value : String) -> (String, String)? {
  match value.split_once("/") {
    Some((adapter, channel_id)) if adapter.length() > 0 && channel_id.length() > 0 =>
      Some((adapter.to_string(), channel_id.to_string()))
    _ => None
  }
}

pub fn InMemoryChannelStore::new() -> InMemoryChannelStore {
  { logs: [] }
}

pub fn InMemoryChannelStore::replace_log(
  self : InMemoryChannelStore,
  adapter : String,
  channel_id : String,
  messages : Array[ChannelMessage]
) -> Unit {
  let normalized = sort_channel_messages(messages.copy())
  for i in 0..<self.logs.length() {
    if self.logs[i].adapter == adapter && self.logs[i].channel_id == channel_id {
      self.logs[i] = { adapter, channel_id, messages: normalized }
      return
    }
  }
  self.logs.push({ adapter, channel_id, messages: normalized })
}

pub fn InMemoryChannelStore::append_message(
  self : InMemoryChannelStore,
  adapter : String,
  message : ChannelMessage
) -> Bool {
  let messages = self.get_log(adapter, message.channel_id)
  for existing in messages {
    if existing.id == message.id {
      return false
    }
  }
  messages.push(message)
  self.replace_log(adapter, message.channel_id, messages)
  true
}

pub fn InMemoryChannelStore::get_log(
  self : InMemoryChannelStore,
  adapter : String,
  channel_id : String
) -> Array[ChannelMessage] {
  for log in self.logs {
    if log.adapter == adapter && log.channel_id == channel_id {
      return log.messages.copy()
    }
  }
  []
}

pub fn InMemoryChannelStore::get_metadata(
  self : InMemoryChannelStore,
  adapter : String,
  channel_id : String
) -> ChannelLogMetadata? {
  let messages = self.get_log(adapter, channel_id)
  if messages.length() == 0 {
    None
  } else {
    Some(channel_log_metadata(adapter, channel_id, messages))
  }
}

pub fn InMemoryChannelStore::list_metadata(self : InMemoryChannelStore) -> Array[ChannelLogMetadata] {
  let metadata : Array[ChannelLogMetadata] = []
  for log in self.logs {
    if log.messages.length() > 0 {
      metadata.push(channel_log_metadata(log.adapter, log.channel_id, log.messages))
    }
  }
  sort_metadata_by_recency(metadata)
}

pub fn serialize_log_jsonl(
  messages : Array[ChannelMessage],
  include_channel_id? : Bool = false
) -> String {
  let lines : Array[String] = []
  for message in messages {
    lines.push(channel_message_to_json(message, include_channel_id~).stringify(escape_slash=false))
  }
  if lines.length() == 0 {
    ""
  } else {
    lines.join("\n") + "\n"
  }
}

pub fn parse_log_jsonl(
  text : String,
  channel_id : String
) -> Result[Array[ChannelMessage], String] {
  let messages : Array[ChannelMessage] = []
  let lines = non_empty_lines(text)
  for i in 0..<lines.length() {
    let json = try @json.parse(lines[i]) catch {
      _error => return Err("failed to parse log.jsonl line " + (i + 1).to_string())
    } noraise {
      value => value
    }
    match channel_message_from_json(json, channel_id) {
      Ok(message) => messages.push(message)
      Err(message) => return Err("invalid log.jsonl line " + (i + 1).to_string() + ": " + message)
    }
  }
  Ok(sort_channel_messages(messages))
}

pub fn channel_message_to_json(
  message : ChannelMessage,
  include_channel_id? : Bool = false
) -> Json {
  if include_channel_id {
    Json::object({
      "id": Json::string(message.id),
      "channelId": Json::string(message.channel_id),
      "timestamp": Json::string(message.timestamp),
      "sender": channel_sender_to_json(message.sender),
      "text": Json::string(message.text),
      "rawText": match message.raw_text {
        Some(text) => Json::string(text)
        None => Json::null()
      },
      "attachments": Json::array(channel_attachments_to_json(message.attachments)),
      "isMention": Json::boolean(message.is_mention),
      "replyTo": match message.reply_to {
        Some(text) => Json::string(text)
        None => Json::null()
      },
      "metadata": match message.metadata {
        Some(value) => value
        None => Json::null()
      },
    })
  } else {
    Json::object({
      "id": Json::string(message.id),
      "timestamp": Json::string(message.timestamp),
      "sender": channel_sender_to_json(message.sender),
      "text": Json::string(message.text),
      "rawText": match message.raw_text {
        Some(text) => Json::string(text)
        None => Json::null()
      },
      "attachments": Json::array(channel_attachments_to_json(message.attachments)),
      "isMention": Json::boolean(message.is_mention),
      "replyTo": match message.reply_to {
        Some(text) => Json::string(text)
        None => Json::null()
      },
      "metadata": match message.metadata {
        Some(value) => value
        None => Json::null()
      },
    })
  }
}

pub fn channel_message_from_json(
  json : Json,
  fallback_channel_id : String
) -> Result[ChannelMessage, String] {
  let channel_id = match first_some_string(
    json_string_field_any(json, ["channelId", "channel_id"]),
    Some(fallback_channel_id),
  ) {
    Some(value) => value
    None => return Err("missing channel id")
  }

  let timestamp = match first_some_string(
    json_string_field_any(json, ["timestamp", "date"]),
    json_string_field_any(json, ["ts"]),
  ) {
    Some(value) => value
    None => return Err("missing timestamp")
  }

  let id = match first_some_string(
    json_string_field_any(json, ["id"]),
    json_string_field_any(json, ["ts", "timestamp", "date"]),
  ) {
    Some(value) => value
    None => return Err("missing message id")
  }

  let sender = match json_object_field(json, "sender") {
    Some(sender_json) =>
      match channel_sender_from_json(sender_json) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
    None => top_level_sender_from_json(json)
  }

  let attachments_json = match json_array_field(json, "attachments") {
    Some(items) => items
    None => []
  }
  let attachments : Array[ChannelAttachment] = []
  for item in attachments_json {
    match channel_attachment_from_json(item) {
      Ok(attachment) => attachments.push(attachment)
      Err(message) => return Err(message)
    }
  }

  Ok({
    id,
    channel_id,
    timestamp,
    sender,
    text: json_string_field_any(json, ["text"]).unwrap_or(""),
    raw_text: json_string_field_any(json, ["rawText", "raw_text"]),
    attachments,
    is_mention: json_bool_field_any(json, ["isMention", "is_mention"]).unwrap_or(false),
    reply_to: json_string_field_any(json, ["replyTo", "reply_to", "threadTs", "thread_ts"]),
    metadata: json_value_field(json, "metadata"),
  })
}

fn channel_log_metadata(
  adapter : String,
  channel_id : String,
  messages : Array[ChannelMessage]
) -> ChannelLogMetadata {
  let sorted = sort_channel_messages(messages.copy())
  let last_message = sorted[sorted.length() - 1]
  {
    adapter,
    channel_id,
    message_count: sorted.length(),
    last_message_at: Some(last_message.timestamp),
    preview: preview_for_message(last_message),
  }
}

fn sort_channel_messages(messages : Array[ChannelMessage]) -> Array[ChannelMessage] {
  let mut remaining = messages.copy()
  let sorted : Array[ChannelMessage] = []
  while remaining.length() > 0 {
    let earliest_index = earliest_message_index(remaining)
    sorted.push(remaining[earliest_index])
    remaining = filter_messages_by_index(remaining, earliest_index)
  }
  sorted
}

fn sort_metadata_by_recency(metadata : Array[ChannelLogMetadata]) -> Array[ChannelLogMetadata] {
  let mut remaining = metadata.copy()
  let sorted : Array[ChannelLogMetadata] = []
  while remaining.length() > 0 {
    let latest_index = latest_metadata_index(remaining)
    sorted.push(remaining[latest_index])
    remaining = filter_metadata_by_index(remaining, latest_index)
  }
  sorted
}

fn earliest_message_index(messages : Array[ChannelMessage]) -> Int {
  let mut earliest_index = 0
  for i in 1..<messages.length() {
    if message_sort_key(messages[i]) < message_sort_key(messages[earliest_index]) {
      earliest_index = i
    }
  }
  earliest_index
}

fn latest_metadata_index(metadata : Array[ChannelLogMetadata]) -> Int {
  let mut latest_index = 0
  for i in 1..<metadata.length() {
    if metadata_sort_key(metadata[i]) > metadata_sort_key(metadata[latest_index]) {
      latest_index = i
    }
  }
  latest_index
}

fn preview_for_message(message : ChannelMessage) -> String {
  let text = message.text.trim().to_string()
  if text.length() > 0 {
    return truncate_preview(text)
  }
  if message.attachments.length() > 0 {
    return truncate_preview("[attachment] " + message.attachments[0].filename)
  }
  ""
}

fn truncate_preview(text : String) -> String {
  if text.length() <= 120 {
    text
  } else {
    text[:117].to_string() + "..."
  }
}

fn channel_sender_to_json(sender : ChannelSender) -> Json {
  Json::object({
    "id": Json::string(sender.id),
    "username": Json::string(sender.username),
    "displayName": match sender.display_name {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "isBot": Json::boolean(sender.is_bot),
  })
}

fn channel_sender_from_json(json : Json) -> Result[ChannelSender, String] {
  let id = match json_string_field_any(json, ["id"]) {
    Some(value) => value
    None => return Err("sender is missing id")
  }
  let username = match first_some_string(
    json_string_field_any(json, ["username", "userName"]),
    Some(id),
  ) {
    Some(value) => value
    None => return Err("sender is missing username")
  }
  Ok({
    id,
    username,
    display_name: json_string_field_any(json, ["displayName", "display_name"]),
    is_bot: json_bool_field_any(json, ["isBot", "is_bot"]).unwrap_or(false),
  })
}

fn top_level_sender_from_json(json : Json) -> ChannelSender {
  let id = json_string_field_any(json, ["user", "userId", "id"]).unwrap_or("unknown")
  {
    id,
    username: first_some_string(
      json_string_field_any(json, ["userName", "username"]),
      Some(id),
    ).unwrap_or(id),
    display_name: json_string_field_any(json, ["displayName", "display_name"]),
    is_bot: json_bool_field_any(json, ["isBot", "is_bot"]).unwrap_or(id == "bot"),
  }
}

fn channel_attachments_to_json(attachments : Array[ChannelAttachment]) -> Array[Json] {
  let items : Array[Json] = []
  for attachment in attachments {
    items.push(Json::object({
      "filename": Json::string(attachment.filename),
      "localPath": Json::string(attachment.local_path),
      "mimeType": match attachment.mime_type {
        Some(value) => Json::string(value)
        None => Json::null()
      },
      "size": match attachment.size {
        Some(value) => Json::number(value.to_double())
        None => Json::null()
      },
    }))
  }
  items
}

fn channel_attachment_from_json(json : Json) -> Result[ChannelAttachment, String] {
  let filename = match first_some_string(
    json_string_field_any(json, ["filename", "original", "name"]),
    None,
  ) {
    Some(value) => value
    None => return Err("attachment is missing filename")
  }
  let local_path = match first_some_string(
    json_string_field_any(json, ["localPath", "local_path", "local"]),
    None,
  ) {
    Some(value) => value
    None => return Err("attachment is missing local path")
  }
  Ok({
    filename,
    local_path,
    mime_type: json_string_field_any(json, ["mimeType", "mime_type"]),
    size: json_int_field_any(json, ["size"]),
  })
}

fn message_sort_key(message : ChannelMessage) -> String {
  message.timestamp + "\n" + message.id
}

fn metadata_sort_key(metadata : ChannelLogMetadata) -> String {
  match metadata.last_message_at {
    Some(timestamp) => timestamp + "\n" + metadata.channel_id
    None => metadata.channel_id
  }
}

fn filter_messages_by_index(messages : Array[ChannelMessage], index : Int) -> Array[ChannelMessage] {
  let filtered : Array[ChannelMessage] = []
  for i in 0..<messages.length() {
    if i != index {
      filtered.push(messages[i])
    }
  }
  filtered
}

fn filter_metadata_by_index(
  metadata : Array[ChannelLogMetadata],
  index : Int
) -> Array[ChannelLogMetadata] {
  let filtered : Array[ChannelLogMetadata] = []
  for i in 0..<metadata.length() {
    if i != index {
      filtered.push(metadata[i])
    }
  }
  filtered
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

fn json_string_field_any(json : Json, keys : Array[String]) -> String? {
  for key in keys {
    match json_string_field(json, key) {
      Some(value) => return Some(value)
      None => ()
    }
  }
  None
}

fn json_bool_field_any(json : Json, keys : Array[String]) -> Bool? {
  for key in keys {
    match json_bool_field(json, key) {
      Some(value) => return Some(value)
      None => ()
    }
  }
  None
}

fn json_int_field_any(json : Json, keys : Array[String]) -> Int? {
  for key in keys {
    match json_int_field(json, key) {
      Some(value) => return Some(value)
      None => ()
    }
  }
  None
}

fn json_string_field(json : Json, key : String) -> String? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(String(value)) => Some(value)
      _ => None
    }
  } else {
    None
  }
}

fn json_bool_field(json : Json, key : String) -> Bool? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(True) => Some(true)
      Some(False) => Some(false)
      _ => None
    }
  } else {
    None
  }
}

fn json_int_field(json : Json, key : String) -> Int? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(Number(value, ..)) => Some(value.to_int())
      _ => None
    }
  } else {
    None
  }
}

fn json_array_field(json : Json, key : String) -> Array[Json]? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(Array(items)) => Some(items.copy())
      _ => None
    }
  } else {
    None
  }
}

fn json_object_field(json : Json, key : String) -> Json? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(value) =>
        if value is Object(_) {
          Some(value)
        } else {
          None
        }
      _ => None
    }
  } else {
    None
  }
}

fn json_value_field(json : Json, key : String) -> Json? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(Null) | None => None
      Some(value) => Some(value)
    }
  } else {
    None
  }
}

fn first_some_string(first : String?, second : String?) -> String? {
  match first {
    Some(value) => Some(value)
    None => second
  }
}

fn mom_join_path(base : String, child : String) -> String {
  if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}
