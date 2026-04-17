test "is_context_overflow detects overflow patterns" {
  let make_msg = fn(error : String) -> AssistantMessage {
    { content: [], api: api_openai_responses, provider: provider_openai, model: "test", usage: Usage::zero(), stop_reason: Error, error_message: Some(error), timestamp: 0.0 }
  }
  assert_true(is_context_overflow(make_msg("prompt is too long: 200000 tokens")))
  assert_true(is_context_overflow(make_msg("maximum context length exceeded")))
  assert_true(is_context_overflow(make_msg("Resource has been exhausted")))
  assert_false(is_context_overflow(make_msg("rate limited")))
  assert_false(is_context_overflow(make_msg("invalid api key")))
  let no_error : AssistantMessage = { content: [], api: api_openai_responses, provider: provider_openai, model: "test", usage: Usage::zero(), stop_reason: Stop, error_message: None, timestamp: 0.0 }
  assert_false(is_context_overflow(no_error))
}
