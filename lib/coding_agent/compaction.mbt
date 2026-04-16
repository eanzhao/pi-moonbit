///| 判断是否需要 compaction（context 接近模型上下文窗口上限）。
pub fn should_compact(
  session_manager : SessionManager,
  model : @ai.Model,
  threshold? : Double = 0.8
) -> Bool {
  let context = session_manager.build_session_context()
  let estimated_tokens = estimate_token_count(context.messages)
  let limit = (model.context_window.to_double() * threshold).to_int()
  estimated_tokens > limit
}

///| 执行 compaction：用摘要替换旧消息，保留最近 N 条。
/// `summarize` 是调用者提供的摘要生成函数（通常调用 LLM）。
/// 返回 compaction entry id。
pub fn run_compaction(
  session_manager : SessionManager,
  summary : String,
  keep_recent? : Int = 10
) -> String {
  let transcript = session_manager.build_transcript_messages()
  if transcript.length() <= keep_recent {
    return ""
  }
  let keep_start = transcript.length() - keep_recent
  let entries = session_manager.get_entries()
  let first_kept_id = find_message_entry_id(entries, transcript[keep_start])
  let tokens_before = estimate_token_count(transcript)
  session_manager.append_compaction(
    summary,
    first_kept_id,
    tokens_before,
  )
}

///| 从 transcript 构建 compaction prompt（让 LLM 总结对话历史）。
pub fn build_compaction_prompt(messages : Array[@ai.Message], keep_recent : Int) -> String {
  if messages.length() <= keep_recent {
    return ""
  }
  let end_index = messages.length() - keep_recent
  let to_summarize : Array[@ai.Message] = []
  let mut idx = 0
  while idx < end_index {
    to_summarize.push(messages[idx])
    idx = idx + 1
  }
  let parts : Array[String] = [
    "Summarize the following conversation history concisely. Preserve key decisions, file changes, and important context. Output only the summary, no preamble.",
    "",
  ]
  for message in to_summarize {
    match message {
      @ai.Message::User(user) => {
        parts.push("User: " + extract_text(user.content))
      }
      @ai.Message::Assistant(assistant) => {
        parts.push("Assistant: " + extract_text(assistant.content))
      }
      @ai.Message::ToolResult(result) => {
        let status = if result.error { " (error)" } else { "" }
        parts.push("Tool[\{result.tool_name}]\{status}: " + extract_text(result.content))
      }
    }
  }
  parts.join("\n")
}

///| 粗略估算消息列表的 token 数（每 4 个字符约 1 token）。
pub fn estimate_token_count(messages : Array[@ai.Message]) -> Int {
  let mut char_count = 0
  for message in messages {
    match message {
      @ai.Message::User(user) =>
        char_count = char_count + content_char_count(user.content)
      @ai.Message::Assistant(assistant) =>
        char_count = char_count + content_char_count(assistant.content)
      @ai.Message::ToolResult(result) =>
        char_count = char_count + content_char_count(result.content)
    }
  }
  (char_count + 3) / 4
}

fn content_char_count(content : Array[@ai.ContentBlock]) -> Int {
  let mut count = 0
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) => count = count + text.length()
      @ai.ContentBlock::Thinking(text) => count = count + text.length()
      @ai.ContentBlock::Image(_) => count = count + 100
      @ai.ContentBlock::ToolCall(tc) =>
        count = count + tc.name.length() + tc.arguments.stringify().length()
    }
  }
  count
}

fn extract_text(content : Array[@ai.ContentBlock]) -> String {
  let parts : Array[String] = []
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) => parts.push(text)
      @ai.ContentBlock::Thinking(text) => parts.push("[thinking] " + text)
      _ => ()
    }
  }
  let joined = parts.join(" ")
  if joined.length() > 200 {
    joined[:200].to_string() + "..."
  } else {
    joined
  }
}

fn find_message_entry_id(
  entries : Array[SessionEntry],
  target_message : @ai.Message
) -> String {
  let target_text = match target_message {
    @ai.Message::User(u) => message_content_text(u.content)
    @ai.Message::Assistant(a) => message_content_text(a.content)
    @ai.Message::ToolResult(t) => t.tool_call_id
  }
  for entry in entries {
    match entry {
      Message(msg_entry) => {
        let entry_text = match msg_entry.message {
          @ai.Message::User(u) => message_content_text(u.content)
          @ai.Message::Assistant(a) => message_content_text(a.content)
          @ai.Message::ToolResult(t) => t.tool_call_id
        }
        if entry_text == target_text {
          return msg_entry.id
        }
      }
      _ => ()
    }
  }
  ""
}

fn message_content_text(content : Array[@ai.ContentBlock]) -> String {
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) => return text
      _ => ()
    }
  }
  ""
}
