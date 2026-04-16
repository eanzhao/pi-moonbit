pub fn build_memory_text(
  global_memory? : String? = None,
  channel_memory? : String? = None
) -> String {
  let sections : Array[String] = []
  match normalized_memory(global_memory) {
    Some(text) => sections.push("### Global Workspace Memory\n" + text)
    None => ()
  }
  match normalized_memory(channel_memory) {
    Some(text) => sections.push("### Channel-Specific Memory\n" + text)
    None => ()
  }
  if sections.length() == 0 {
    "(no working memory yet)"
  } else {
    sections.join("\n\n")
  }
}

pub fn channel_message_to_context_text(message : ChannelMessage) -> String {
  let speaker = if message.sender.username.length() > 0 {
    message.sender.username
  } else {
    message.sender.id
  }
  let mut text = "[" + speaker + "]:"
  if message.text.length() > 0 {
    text = text + " " + message.text
  }

  if message.attachments.length() == 0 {
    return text
  }

  let attachment_lines : Array[String] = []
  for attachment in message.attachments {
    attachment_lines.push("- " + attachment.filename + " (" + attachment.local_path + ")")
  }
  text + "\n\n<attachments>\n" + attachment_lines.join("\n") + "\n</attachments>"
}

pub fn channel_message_to_user_message(message : ChannelMessage) -> @ai.UserMessage {
  {
    content: [@ai.ContentBlock::Text(channel_message_to_context_text(message))],
  }
}

pub fn sync_channel_log_to_session_manager(
  session_manager : @coding_agent.SessionManager,
  log_messages : Array[ChannelMessage],
  exclude_message_id? : String? = None
) -> Int {
  let existing = existing_user_context_texts(session_manager.build_transcript_messages())
  let queued : Array[(String, String, @ai.UserMessage)] = []

  for message in log_messages {
    if message.sender.is_bot {
      continue
    }
    match exclude_message_id {
      Some(id) if message.id == id => continue
      _ => ()
    }

    let context_text = channel_message_to_context_text(message)
    if array_contains(existing, context_text) {
      continue
    }
    if queued_contains(queued, context_text) {
      continue
    }
    queued.push((message.timestamp, context_text, channel_message_to_user_message(message)))
  }

  let sorted = sort_queued_messages(queued)
  for item in sorted {
    let (timestamp, text, user_message) = item
    ignore(session_manager.append_message(@ai.Message::User(user_message), timestamp=timestamp))
    existing.push(text)
  }

  sorted.length()
}

fn normalized_memory(text : String?) -> String? {
  match text {
    Some(value) => {
      let trimmed = value.trim().to_string()
      if trimmed.length() == 0 {
        None
      } else {
        Some(trimmed)
      }
    }
    None => None
  }
}

fn existing_user_context_texts(messages : Array[@ai.Message]) -> Array[String] {
  let texts : Array[String] = []
  for message in messages {
    match message {
      @ai.Message::User(user_message) => {
        let text = ai_content_text(user_message.content)
        if text.length() > 0 && !array_contains(texts, text) {
          texts.push(text)
        }
      }
      _ => ()
    }
  }
  texts
}

fn ai_content_text(content : Array[@ai.ContentBlock]) -> String {
  let parts : Array[String] = []
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) => parts.push(text)
      _ => ()
    }
  }
  parts.join("")
}

fn array_contains(items : Array[String], value : String) -> Bool {
  for item in items {
    if item == value {
      return true
    }
  }
  false
}

fn queued_contains(
  items : Array[(String, String, @ai.UserMessage)],
  value : String
) -> Bool {
  for item in items {
    let (_timestamp, text, _message) = item
    if text == value {
      return true
    }
  }
  false
}

fn sort_queued_messages(
  items : Array[(String, String, @ai.UserMessage)]
) -> Array[(String, String, @ai.UserMessage)] {
  let mut remaining = items.copy()
  let sorted : Array[(String, String, @ai.UserMessage)] = []
  while remaining.length() > 0 {
    let earliest_index = earliest_queued_index(remaining)
    sorted.push(remaining[earliest_index])
    remaining = filter_queued_by_index(remaining, earliest_index)
  }
  sorted
}

fn earliest_queued_index(items : Array[(String, String, @ai.UserMessage)]) -> Int {
  let mut earliest_index = 0
  for i in 1..<items.length() {
    if queued_sort_key(items[i]) < queued_sort_key(items[earliest_index]) {
      earliest_index = i
    }
  }
  earliest_index
}

fn queued_sort_key(item : (String, String, @ai.UserMessage)) -> String {
  let (timestamp, text, _message) = item
  timestamp + "\n" + text
}

fn filter_queued_by_index(
  items : Array[(String, String, @ai.UserMessage)],
  index : Int
) -> Array[(String, String, @ai.UserMessage)] {
  let filtered : Array[(String, String, @ai.UserMessage)] = []
  for i in 0..<items.length() {
    if i != index {
      filtered.push(items[i])
    }
  }
  filtered
}
