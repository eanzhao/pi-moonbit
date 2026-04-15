test "register and get provider" {
  clear_providers()
  register_provider(api_anthropic_messages, fn(_model, _ctx, _opts, _handler) {
  })
  match get_provider(api_anthropic_messages) {
    Some(_) => ()
    None => fail("expected provider to be registered")
  }
  match get_provider(api_openai_completions) {
    None => ()
    Some(_) => fail("expected no provider for unregistered API")
  }
  clear_providers()
}

test "stream raises error for unregistered API" {
  clear_providers()
  let model : Model = {
    id: "test-model",
    name: "Test",
    api: ApiId("nonexistent-api"),
    provider: ProviderId("test"),
    base_url: None,
    reasoning: false,
    input_modalities: [Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 4096,
    max_tokens: 1024,
  }
  let ctx : Context = { system_prompt: None, messages: [], tools: [] }
  let opts = StreamOptions::default()
  let mut got_error = false
  try {
    stream(model, ctx, opts, EventHandler(fn(_) { }))
  } catch {
    StreamError(_) => got_error = true
  }
  assert_true(got_error)
  clear_providers()
}

test "stream delegates to registered provider" {
  clear_providers()
  let events : Array[AssistantMessageEvent] = []
  let fake_msg : AssistantMessage = {
    content: [Text("hello from fake")],
    api: api_anthropic_messages,
    provider: provider_anthropic,
    model: "fake-model",
    usage: Usage::zero(),
    stop_reason: Stop,
    error_message: None,
    timestamp: 0.0,
  }
  register_provider(api_anthropic_messages, fn(_model, _ctx, _opts, handler) {
    handler.0(TextDelta(0, "hello"))
    handler.0(Done(Stop, fake_msg))
  })
  let model : Model = {
    id: "fake-model",
    name: "Fake",
    api: api_anthropic_messages,
    provider: provider_anthropic,
    base_url: None,
    reasoning: false,
    input_modalities: [Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 4096,
    max_tokens: 1024,
  }
  let ctx : Context = { system_prompt: None, messages: [], tools: [] }
  stream(model, ctx, StreamOptions::default(), EventHandler(fn(event) { events.push(event) }))
  assert_eq(events.length(), 2)
  match events[0] {
    TextDelta(idx, delta) => {
      assert_eq(idx, 0)
      assert_eq(delta, "hello")
    }
    _ => fail("expected TextDelta")
  }
  assert_true(is_terminal(events[1]))
  clear_providers()
}

test "complete collects final message" {
  clear_providers()
  let fake_msg : AssistantMessage = {
    content: [Text("completed")],
    api: api_anthropic_messages,
    provider: provider_anthropic,
    model: "fake-model",
    usage: Usage::zero(),
    stop_reason: Stop,
    error_message: None,
    timestamp: 0.0,
  }
  register_provider(api_anthropic_messages, fn(_model, _ctx, _opts, handler) {
    handler.0(Start(fake_msg))
    handler.0(TextDelta(0, "completed"))
    handler.0(Done(Stop, fake_msg))
  })
  let model : Model = {
    id: "fake-model",
    name: "Fake",
    api: api_anthropic_messages,
    provider: provider_anthropic,
    base_url: None,
    reasoning: false,
    input_modalities: [Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 4096,
    max_tokens: 1024,
  }
  let ctx : Context = { system_prompt: None, messages: [], tools: [] }
  let result = complete(model, ctx, StreamOptions::default())
  assert_eq(result.model, "fake-model")
  match result.content[0] {
    Text(t) => assert_eq(t, "completed")
    _ => fail("expected Text content")
  }
  clear_providers()
}
