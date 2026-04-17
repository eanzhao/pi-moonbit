test "nyxid api and provider constants" {
  assert_eq(api_nyxid_gateway, ApiId("nyxid-gateway"))
  assert_eq(provider_nyxid, ProviderId("nyxid"))
  assert_not_eq(api_nyxid_gateway, api_openai_completions)
  assert_not_eq(provider_nyxid, provider_openai)
}

test "nyxid gateway reuses openai request body format" {
  // NyxID gateway is OpenAI-compatible, so build_openai_request_body works for it.
  let model : Model = {
    id: "claude-sonnet-4-5-20250929",
    name: "Claude Sonnet 4.5 (via NyxID)",
    api: api_nyxid_gateway,
    provider: provider_nyxid,
    base_url: Some("https://nyx.chrono-ai.fun"),
    reasoning: true,
    input_modalities: [Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 200000,
    max_tokens: 8192,
  }
  let context : Context = {
    system_prompt: Some("You are helpful"),
    messages: [User({ content: [Text("hi")] })],
    tools: [],
  }
  let body = build_openai_request_body(model, context, StreamOptions::default())
  match body {
    Object(obj) => {
      match obj.get("model") {
        Some(String(m)) => assert_eq(m, "claude-sonnet-4-5-20250929")
        _ => fail("expected model")
      }
      match obj.get("messages") {
        Some(Array(msgs)) => assert_true(msgs.length() >= 2) // system + user
        _ => fail("expected messages")
      }
    }
    _ => fail("expected object")
  }
}
