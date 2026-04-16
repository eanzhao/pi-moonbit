test "estimate_token_count approximates from character length" {
  let messages : Array[@ai.Message] = [
    @ai.Message::User({ content: [@ai.ContentBlock::Text("hello world")] }),
    @ai.Message::Assistant({
      content: [@ai.ContentBlock::Text("hi there")],
      api: @ai.api_openai_completions,
      provider: @ai.provider_openai,
      model: "test",
      usage: @ai.Usage::zero(),
      stop_reason: @ai.StopReason::Stop,
      error_message: None,
      timestamp: 0.0,
    }),
  ]
  let tokens = estimate_token_count(messages)
  assert_true(tokens > 0)
  assert_true(tokens < 20)
}

test "should_compact returns true when context exceeds threshold" {
  let sm = SessionManager::new(session_id="compact-test")
  let mut big_text = ""
  let mut i = 0
  while i < 10000 {
    big_text = big_text + "word "
    i = i + 1
  }
  ignore(sm.append_message(@ai.Message::User({
    content: [@ai.ContentBlock::Text(big_text)],
  })))
  let small_model : @ai.Model = {
    id: "small",
    name: "small",
    api: @ai.api_openai_completions,
    provider: @ai.provider_openai,
    base_url: None,
    reasoning: false,
    input_modalities: [@ai.InputModality::Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 4096,
    max_tokens: 1024,
  }
  assert_true(should_compact(sm, small_model))
}

test "run_compaction creates compaction entry and context respects it" {
  let sm = SessionManager::new(session_id="compact-run")
  let mut i = 0
  while i < 15 {
    ignore(sm.append_message(@ai.Message::User({
      content: [@ai.ContentBlock::Text("msg " + i.to_string())],
    })))
    i = i + 1
  }
  let transcript_before = sm.build_transcript_messages()
  assert_eq(transcript_before.length(), 15)

  let id = run_compaction(sm, "Summary of first 5 messages", keep_recent=10)
  assert_true(id.length() > 0)

  let context = sm.build_session_context()
  assert_true(context.messages.length() <= 12)
  assert_true(context.messages.length() >= 10)
}

test "build_compaction_prompt generates summary request" {
  let messages : Array[@ai.Message] = []
  let mut i = 0
  while i < 5 {
    messages.push(@ai.Message::User({
      content: [@ai.ContentBlock::Text("question " + i.to_string())],
    }))
    i = i + 1
  }
  let prompt = build_compaction_prompt(messages, 2)
  assert_true(prompt.contains("Summarize"))
  assert_true(prompt.contains("question 0"))
  assert_true(prompt.contains("question 2"))
}
