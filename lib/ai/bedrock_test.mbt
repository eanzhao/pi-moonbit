test "bedrock request body includes system and messages" {
  let model : Model = {
    id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
    name: "Claude Sonnet (Bedrock)",
    api: api_bedrock,
    provider: provider_bedrock,
    base_url: None,
    reasoning: false,
    input_modalities: [Text],
    cost: { input: 3.0, output: 15.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 200000,
    max_tokens: 4096,
  }
  let context : Context = {
    system_prompt: Some("You are helpful"),
    messages: [User({ content: [Text("hi")] })],
    tools: [],
  }
  let body = build_bedrock_request_body(model, context, StreamOptions::default())
  match body {
    Object(obj) => {
      assert_true(obj.get("system") is Some(_))
      assert_true(obj.get("messages") is Some(_))
      assert_true(obj.get("inferenceConfig") is Some(_))
    }
    _ => fail("expected object")
  }
}

test "bedrock stop reason mapping" {
  assert_eq(bedrock_stop_reason_to_stop_reason("end_turn"), Stop)
  assert_eq(bedrock_stop_reason_to_stop_reason("max_tokens"), Length)
  assert_eq(bedrock_stop_reason_to_stop_reason("tool_use"), ToolUse)
  assert_eq(bedrock_stop_reason_to_stop_reason("unknown"), Error)
}

test "vertex url construction" {
  let url = build_vertex_url("my-project", "us-central1", "gemini-2.0-flash")
  assert_true(url.contains("my-project"))
  assert_true(url.contains("us-central1"))
  assert_true(url.contains("gemini-2.0-flash"))
  assert_true(url.contains(":streamGenerateContent"))
}

test "azure url construction" {
  let url = build_azure_url("my-resource", "gpt-4o")
  assert_true(url.contains("my-resource.openai.azure.com"))
  assert_true(url.contains("deployments/gpt-4o"))
  assert_true(url.contains("api-version="))
}
