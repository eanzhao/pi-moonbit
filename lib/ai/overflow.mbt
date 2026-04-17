pub fn is_context_overflow(message : AssistantMessage) -> Bool {
  match message.error_message {
    Some(error) => matches_overflow_pattern(error)
    None => false
  }
}

fn matches_overflow_pattern(error : String) -> Bool {
  let lower = error.to_lower()
  let patterns = [
    "prompt is too long",
    "maximum context length",
    "context length exceeded",
    "context_length_exceeded",
    "too many tokens",
    "token limit",
    "resource has been exhausted",
    "request too large",
    "input is too long",
    "exceeds the model's maximum context",
    "sequence is too long",
    "reduce your prompt",
    "payload too large",
    "content length limit",
  ]
  for pattern in patterns {
    if lower.contains(pattern) { return true }
  }
  false
}
