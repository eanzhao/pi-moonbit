fn gemini_test_model(base_url? : String? = None) -> Model {
  {
    id: "gemini-2.5-flash",
    name: "Gemini 2.5 Flash",
    api: api_google_genai,
    provider: provider_google,
    base_url,
    reasoning: false,
    input_modalities: [Text, Image],
    cost: { input: 0.1, output: 0.4, cache_read: 0.025, cache_write: 0.0 },
    context_window: 1_000_000,
    max_tokens: 8192,
  }
}

fn gemini_test_options(
  temperature? : Double? = None,
  max_tokens? : Int? = None,
  top_p? : Double? = None,
) -> StreamOptions {
  {
    temperature,
    max_tokens,
    top_p,
    api_key: None,
    cache_retention: None,
    retry_count: None,
    retry_delay_ms: None,
    thinking_mode: None,
    thinking_budget_tokens: None,
    reasoning: None,
  }
}

fn gemini_test_assistant_message(
  content : Array[ContentBlock],
  stop_reason? : StopReason = Stop
) -> Message {
  Assistant({
    content,
    api: api_google_genai,
    provider: provider_google,
    model: "gemini-2.5-flash",
    usage: Usage::zero(),
    stop_reason,
    error_message: None,
    timestamp: 0.0,
  })
}

fn gemini_sse_line(payload : Json) -> String {
  "data: " + payload.stringify(escape_slash=false)
}

test "build Gemini URL from default and custom base URL" {
  let default_url = build_gemini_url(gemini_test_model(), "secret")
  assert_eq(
    default_url,
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?key=secret&alt=sse",
  )

  let custom_url = build_gemini_url(
    gemini_test_model(base_url=Some("https://example.com/custom/")),
    "key2",
  )
  assert_eq(
    custom_url,
    "https://example.com/custom/models/gemini-2.5-flash:streamGenerateContent?key=key2&alt=sse",
  )
}

test "build request body with system prompt and generation config" {
  let context : Context = {
    system_prompt: Some("You are concise."),
    messages: [User({ content: [Text("Hello")] })],
    tools: [],
  }
  let body = build_gemini_request_body(
    gemini_test_model(),
    context,
    gemini_test_options(temperature=Some(0.2), max_tokens=Some(256), top_p=Some(0.9)),
  )

  guard body is Object({
    "contents": Array(contents),
    "generationConfig": Object({
      "maxOutputTokens": Number(max_output_tokens, ..),
      "temperature": Number(temperature, ..),
      "topP": Number(top_p, ..),
      ..
    }),
    "systemInstruction": Object({
      "parts": Array(system_parts),
      ..
    }),
    ..
  }) else {
    fail("expected Gemini request body object")
  }

  assert_eq(contents.length(), 1)
  assert_eq(max_output_tokens.to_int(), 256)
  assert_eq(temperature, 0.2)
  assert_eq(top_p, 0.9)

  guard system_parts[0] is Object({
    "text": String(system_text),
    ..
  }) else {
    fail("expected system instruction text part")
  }
  assert_eq(system_text, "You are concise.")

  guard contents[0] is Object({
    "role": String(role),
    "parts": Array(parts),
    ..
  }) else {
    fail("expected Gemini user content")
  }
  assert_eq(role, "user")
  assert_eq(parts.length(), 1)
  guard parts[0] is Object({
    "text": String(text),
    ..
  }) else {
    fail("expected user text part")
  }
  assert_eq(text, "Hello")
}

test "build request body with tools and tool messages" {
  let tool_call : ToolCall = {
    id: "call_1",
    name: "lookup_weather",
    arguments: Json::object({ "city": Json::string("Paris") }),
  }
  let context : Context = {
    system_prompt: None,
    messages: [
      gemini_test_assistant_message([
        Text("Checking weather."),
        ContentBlock::ToolCall(tool_call),
      ], stop_reason=ToolUse),
      ToolResult({
        content: [Text("sunny")],
        tool_call_id: "call_1",
        tool_name: "lookup_weather",
        error: false,
      }),
    ],
    tools: [
      {
        name: "lookup_weather",
        description: "Look up weather by city",
        parameters: Json::object({
          "type": Json::string("object"),
          "properties": Json::object({
            "city": Json::object({ "type": Json::string("string") }),
          }),
        }),
      },
    ],
  }

  let body = build_gemini_request_body(gemini_test_model(), context, gemini_test_options())

  guard body is Object({
    "contents": Array(contents),
    "tools": Array(tools),
    ..
  }) else {
    fail("expected Gemini request body with tools")
  }

  assert_eq(contents.length(), 2)
  assert_eq(tools.length(), 1)

  guard tools[0] is Object({
    "functionDeclarations": Array(declarations),
    ..
  }) else {
    fail("expected Gemini functionDeclarations wrapper")
  }
  assert_eq(declarations.length(), 1)
  guard declarations[0] is Object({
    "name": String(tool_name),
    "description": String(tool_description),
    "parameters": Object(_),
    ..
  }) else {
    fail("expected Gemini tool declaration")
  }
  assert_eq(tool_name, "lookup_weather")
  assert_eq(tool_description, "Look up weather by city")

  guard contents[0] is Object({
    "role": String(model_role),
    "parts": Array(model_parts),
    ..
  }) else {
    fail("expected Gemini assistant content")
  }
  assert_eq(model_role, "model")
  assert_eq(model_parts.length(), 2)
  guard model_parts[1] is Object({
    "functionCall": Object({
      "name": String(function_name),
      "args": Object({ "city": String(city), .. }),
      ..
    }),
    ..
  }) else {
    fail("expected functionCall part")
  }
  assert_eq(function_name, "lookup_weather")
  assert_eq(city, "Paris")

  guard contents[1] is Object({
    "role": String(user_role),
    "parts": Array(user_parts),
    ..
  }) else {
    fail("expected tool result user content")
  }
  assert_eq(user_role, "user")
  assert_eq(user_parts.length(), 1)
  guard user_parts[0] is Object({
    "functionResponse": Object({
      "name": String(response_name),
      "response": Object({
        "result": String(result_text),
        ..
      }),
      ..
    }),
    ..
  }) else {
    fail("expected functionResponse part")
  }
  assert_eq(response_name, "lookup_weather")
  assert_eq(result_text, "sunny")
}

test "parse Gemini SSE text delta and finish chunk" {
  let state = GeminiStreamState::new(gemini_test_model())
  let first_events = parse_gemini_sse_line(
    gemini_sse_line(Json::object({
      "candidates": Json::array([
        Json::object({
          "content": Json::object({
            "role": Json::string("model"),
            "parts": Json::array([
              Json::object({
                "text": Json::string("Hel"),
              }),
            ]),
          }),
        }),
      ]),
    })),
    state,
  )

  assert_eq(first_events.length(), 3)
  assert_true(first_events[0] is Start(_))
  match first_events[1] {
    TextStart(index) => assert_eq(index, 0)
    _ => fail("expected TextStart")
  }
  match first_events[2] {
    TextDelta(index, delta) => {
      assert_eq(index, 0)
      assert_eq(delta, "Hel")
    }
    _ => fail("expected TextDelta")
  }

  let second_events = parse_gemini_sse_line(
    gemini_sse_line(Json::object({
      "candidates": Json::array([
        Json::object({
          "content": Json::object({
            "role": Json::string("model"),
            "parts": Json::array([
              Json::object({
                "text": Json::string("lo"),
              }),
            ]),
          }),
          "finishReason": Json::string("STOP"),
        }),
      ]),
      "usageMetadata": Json::object({
        "promptTokenCount": Json::number(10.0),
        "candidatesTokenCount": Json::number(5.0),
        "totalTokenCount": Json::number(15.0),
      }),
    })),
    state,
  )

  assert_eq(second_events.length(), 3)
  match second_events[0] {
    TextDelta(index, delta) => {
      assert_eq(index, 0)
      assert_eq(delta, "lo")
    }
    _ => fail("expected TextDelta")
  }
  match second_events[1] {
    TextEnd(index, text) => {
      assert_eq(index, 0)
      assert_eq(text, "Hello")
    }
    _ => fail("expected TextEnd")
  }
  match second_events[2] {
    Done(reason, message) => {
      assert_eq(reason, Stop)
      assert_eq(message.stop_reason, Stop)
      assert_eq(message.usage.input, 10)
      assert_eq(message.usage.output, 5)
      assert_eq(message.usage.total_tokens, 15)
      match message.content[0] {
        Text(text) => assert_eq(text, "Hello")
        _ => fail("expected final text content")
      }
    }
    _ => fail("expected Done event")
  }
}

test "parse Gemini SSE function call and map stop to tool use" {
  let state = GeminiStreamState::new(gemini_test_model())
  let first_events = parse_gemini_sse_line(
    gemini_sse_line(Json::object({
      "candidates": Json::array([
        Json::object({
          "content": Json::object({
            "role": Json::string("model"),
            "parts": Json::array([
              Json::object({
                "functionCall": Json::object({
                  "name": Json::string("lookup_weather"),
                  "args": Json::object({
                    "city": Json::string("Paris"),
                  }),
                }),
              }),
            ]),
          }),
        }),
      ]),
    })),
    state,
  )

  assert_eq(first_events.length(), 4)
  assert_true(first_events[0] is Start(_))
  let mut tool_call_id = ""
  match first_events[1] {
    ToolCallStart(index, tool_call) => {
      assert_eq(index, 0)
      assert_eq(tool_call.name, "lookup_weather")
      assert_true(tool_call.id.length() > 0)
      tool_call_id = tool_call.id
    }
    _ => fail("expected ToolCallStart")
  }
  match first_events[2] {
    ToolCallDelta(index, delta) => {
      assert_eq(index, 0)
      assert_true(delta.contains("\"city\""))
    }
    _ => fail("expected ToolCallDelta")
  }
  match first_events[3] {
    ToolCallEnd(index, tool_call) => {
      assert_eq(index, 0)
      assert_eq(tool_call.id, tool_call_id)
      guard tool_call.arguments is Object({ "city": String(city), .. }) else {
        fail("expected parsed Gemini tool call arguments")
      }
      assert_eq(city, "Paris")
    }
    _ => fail("expected ToolCallEnd")
  }

  let second_events = parse_gemini_sse_line(
    gemini_sse_line(Json::object({
      "candidates": Json::array([
        Json::object({
          "finishReason": Json::string("STOP"),
        }),
      ]),
      "usageMetadata": Json::object({
        "promptTokenCount": Json::number(12.0),
        "candidatesTokenCount": Json::number(3.0),
        "totalTokenCount": Json::number(15.0),
      }),
    })),
    state,
  )

  assert_eq(second_events.length(), 1)
  match second_events[0] {
    Done(reason, message) => {
      assert_eq(reason, ToolUse)
      assert_eq(message.stop_reason, ToolUse)
      assert_eq(message.usage.total_tokens, 15)
      match message.content[0] {
        ContentBlock::ToolCall(tool_call) => assert_eq(tool_call.id, tool_call_id)
        _ => fail("expected final tool call content")
      }
    }
    _ => fail("expected Done tool use event")
  }
}

test "parse Gemini synthetic done marker" {
  let state = GeminiStreamState::new(gemini_test_model())
  ignore(parse_gemini_sse_line(
    gemini_sse_line(Json::object({
      "candidates": Json::array([
        Json::object({
          "content": Json::object({
            "parts": Json::array([
              Json::object({
                "text": Json::string("hello"),
              }),
            ]),
          }),
        }),
      ]),
    })),
    state,
  ))

  let events = parse_gemini_sse_line("data: [DONE]", state)
  assert_eq(events.length(), 2)
  match events[0] {
    TextEnd(index, text) => {
      assert_eq(index, 0)
      assert_eq(text, "hello")
    }
    _ => fail("expected TextEnd")
  }
  match events[1] {
    Done(reason, message) => {
      assert_eq(reason, Stop)
      assert_eq(message.stop_reason, Stop)
    }
    _ => fail("expected Done")
  }
}
