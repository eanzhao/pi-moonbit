test "is_terminal" {
  let done_event = AssistantMessageEvent::Done(Stop, {
    content: [Text("done")],
    api: api_anthropic_messages,
    provider: provider_anthropic,
    model: "claude-sonnet-4-20250514",
    usage: Usage::zero(),
    stop_reason: Stop,
    error_message: None,
    timestamp: 0.0,
  })
  let error_event = AssistantMessageEvent::Error(Error, {
    content: [],
    api: api_anthropic_messages,
    provider: provider_anthropic,
    model: "claude-sonnet-4-20250514",
    usage: Usage::zero(),
    stop_reason: Error,
    error_message: Some("rate limited"),
    timestamp: 0.0,
  })
  let text_event = AssistantMessageEvent::TextDelta(0, "hello")
  assert_true(is_terminal(done_event))
  assert_true(is_terminal(error_event))
  assert_false(is_terminal(text_event))
  assert_false(is_terminal(TextStart(0)))
}

test "final_message extracts from terminal events" {
  let msg : AssistantMessage = {
    content: [Text("result")],
    api: api_openai_responses,
    provider: provider_openai,
    model: "gpt-4o",
    usage: Usage::zero(),
    stop_reason: Stop,
    error_message: None,
    timestamp: 1234567890.0,
  }
  let done = AssistantMessageEvent::Done(Stop, msg)
  match final_message(done) {
    Some(m) => assert_eq(m.model, "gpt-4o")
    None => fail("expected Some")
  }
  let non_terminal = AssistantMessageEvent::ThinkingDelta(0, "thinking...")
  match final_message(non_terminal) {
    None => ()
    Some(_) => fail("expected None for non-terminal")
  }
}
