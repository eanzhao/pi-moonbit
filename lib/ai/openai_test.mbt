fn openai_test_model() -> Model {
  {
    id: "gpt-4o-mini",
    name: "GPT-4o Mini",
    api: api_openai_completions,
    provider: provider_openai,
    base_url: None,
    reasoning: false,
    input_modalities: [Text],
    cost: { input: 0.15, output: 0.6, cache_read: 0.0, cache_write: 0.0 },
    context_window: 128_000,
    max_tokens: 4096,
  }
}

fn openai_test_options(
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

fn openai_test_assistant_message(content : Array[ContentBlock], stop_reason? : StopReason = Stop) -> Message {
  Assistant({
    content,
    api: api_openai_completions,
    provider: provider_openai,
    model: "gpt-4o-mini",
    usage: Usage::zero(),
    stop_reason,
    error_message: None,
    timestamp: 0.0,
  })
}

fn sse_line(payload : Json) -> String {
  "data: " + payload.stringify(escape_slash=false)
}

test "build request body from simple context" {
  let model = openai_test_model()
  let context : Context = {
    system_prompt: Some("You are concise."),
    messages: [User({ content: [Text("Hello")] })],
    tools: [],
  }
  let body = build_openai_request_body(
    model,
    context,
    openai_test_options(temperature=Some(0.2), max_tokens=Some(128)),
  )

  guard body is Object({
    "model": String(model_id),
    "messages": Array(messages),
    "stream": True,
    "max_tokens": Number(max_tokens, ..),
    "temperature": Number(temperature, ..),
    "stream_options": Object({ "include_usage": True, .. }),
    ..
  }) else {
    fail("expected OpenAI request body object")
  }

  assert_eq(model_id, "gpt-4o-mini")
  assert_eq(max_tokens.to_int(), 128)
  assert_eq(temperature, 0.2)
  assert_eq(messages.length(), 2)

  guard messages[0] is Object({
    "role": String(system_role),
    "content": String(system_content),
    ..
  }) else {
    fail("expected system message")
  }
  assert_eq(system_role, "system")
  assert_eq(system_content, "You are concise.")

  guard messages[1] is Object({
    "role": String(user_role),
    "content": String(user_content),
    ..
  }) else {
    fail("expected user message")
  }
  assert_eq(user_role, "user")
  assert_eq(user_content, "Hello")
}

test "build request body with tool definitions and tool messages" {
  let tool_call : ToolCall = {
    id: "call_1",
    name: "lookup_weather",
    arguments: Json::object({ "city": Json::string("Paris") }),
  }
  let context : Context = {
    system_prompt: None,
    messages: [
      openai_test_assistant_message([ContentBlock::ToolCall(tool_call)], stop_reason=ToolUse),
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

  let body = build_openai_request_body(openai_test_model(), context, openai_test_options())

  guard body is Object({
    "messages": Array(messages),
    "tools": Array(tools),
    ..
  }) else {
    fail("expected request body with messages and tools")
  }

  assert_eq(messages.length(), 2)
  assert_eq(tools.length(), 1)

  guard tools[0] is Object({
    "type": String(tool_type),
    "function": Object({
      "name": String(tool_name),
      "description": String(tool_description),
      "parameters": Object(_),
      ..
    }),
    ..
  }) else {
    fail("expected OpenAI tool definition")
  }
  assert_eq(tool_type, "function")
  assert_eq(tool_name, "lookup_weather")
  assert_eq(tool_description, "Look up weather by city")

  guard messages[0] is Object({
    "role": String(assistant_role),
    "content": Null,
    "tool_calls": Array(tool_calls),
    ..
  }) else {
    fail("expected assistant tool call message")
  }
  assert_eq(assistant_role, "assistant")
  assert_eq(tool_calls.length(), 1)

  guard tool_calls[0] is Object({
    "id": String(tool_call_id),
    "type": String(tool_call_type),
    "function": Object({
      "name": String(tool_call_name),
      "arguments": String(tool_call_arguments),
      ..
    }),
    ..
  }) else {
    fail("expected serialized assistant tool call")
  }
  assert_eq(tool_call_id, "call_1")
  assert_eq(tool_call_type, "function")
  assert_eq(tool_call_name, "lookup_weather")
  assert_true(tool_call_arguments.contains("\"city\""))

  guard messages[1] is Object({
    "role": String(tool_role),
    "tool_call_id": String(tool_result_id),
    "content": String(tool_content),
    ..
  }) else {
    fail("expected tool result message")
  }
  assert_eq(tool_role, "tool")
  assert_eq(tool_result_id, "call_1")
  assert_eq(tool_content, "sunny")
}

test "parse SSE text delta chunks" {
  let state = OpenAiStreamState::new(openai_test_model())
  let first_events = parse_openai_sse_line(
    sse_line(Json::object({
      "choices": Json::array([
        Json::object({
          "delta": Json::object({
            "role": Json::string("assistant"),
            "content": Json::string("Hel"),
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

  let second_events = parse_openai_sse_line(
    sse_line(Json::object({
      "choices": Json::array([
        Json::object({
          "delta": Json::object({
            "content": Json::string("lo"),
          }),
        }),
      ]),
    })),
    state,
  )
  assert_eq(second_events.length(), 1)
  match second_events[0] {
    TextDelta(index, delta) => {
      assert_eq(index, 0)
      assert_eq(delta, "lo")
    }
    _ => fail("expected TextDelta")
  }

  match state.content[0] {
    Text(text) => assert_eq(text, "Hello")
    _ => fail("expected accumulated text content")
  }
}

test "parse SSE tool call chunks" {
  let state = OpenAiStreamState::new(openai_test_model())

  let first_events = parse_openai_sse_line(
    sse_line(Json::object({
      "choices": Json::array([
        Json::object({
          "delta": Json::object({
            "tool_calls": Json::array([
              Json::object({
                "index": Json::number(0.0),
                "id": Json::string("call_1"),
                "type": Json::string("function"),
                "function": Json::object({
                  "name": Json::string("lookup_weather"),
                  "arguments": Json::string("{\"city\":\"San"),
                }),
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
    ToolCallStart(index, tool_call) => {
      assert_eq(index, 0)
      assert_eq(tool_call.id, "call_1")
      assert_eq(tool_call.name, "lookup_weather")
    }
    _ => fail("expected ToolCallStart")
  }
  match first_events[2] {
    ToolCallDelta(index, delta) => {
      assert_eq(index, 0)
      assert_eq(delta, "{\"city\":\"San")
    }
    _ => fail("expected ToolCallDelta")
  }

  let second_events = parse_openai_sse_line(
    sse_line(Json::object({
      "choices": Json::array([
        Json::object({
          "delta": Json::object({
            "tool_calls": Json::array([
              Json::object({
                "index": Json::number(0.0),
                "function": Json::object({
                  "arguments": Json::string(" Francisco\"}"),
                }),
              }),
            ]),
          }),
          "finish_reason": Json::string("tool_calls"),
        }),
      ]),
      "usage": Json::object({
        "prompt_tokens": Json::number(10.0),
        "completion_tokens": Json::number(5.0),
        "total_tokens": Json::number(15.0),
      }),
    })),
    state,
  )

  assert_eq(second_events.length(), 3)
  match second_events[0] {
    ToolCallDelta(index, delta) => {
      assert_eq(index, 0)
      assert_eq(delta, " Francisco\"}")
    }
    _ => fail("expected ToolCallDelta")
  }
  match second_events[1] {
    ToolCallEnd(index, tool_call) => {
      assert_eq(index, 0)
      assert_eq(tool_call.id, "call_1")
      assert_eq(tool_call.name, "lookup_weather")
      guard tool_call.arguments is Object({ "city": String(city), .. }) else {
        fail("expected parsed tool call arguments")
      }
      assert_eq(city, "San Francisco")
    }
    _ => fail("expected ToolCallEnd")
  }
  match second_events[2] {
    Done(reason, message) => {
      assert_eq(reason, ToolUse)
      assert_eq(message.stop_reason, ToolUse)
      assert_eq(message.usage.total_tokens, 15)
    }
    _ => fail("expected terminal Done event")
  }
}

test "parse SSE done stop chunk" {
  let state = OpenAiStreamState::new(openai_test_model())
  ignore(parse_openai_sse_line(
    sse_line(Json::object({
      "choices": Json::array([
        Json::object({
          "delta": Json::object({
            "content": Json::string("hello"),
          }),
        }),
      ]),
    })),
    state,
  ))

  let events = parse_openai_sse_line(
    sse_line(Json::object({
      "choices": Json::array([
        Json::object({
          "delta": Json::object({}),
          "finish_reason": Json::string("stop"),
        }),
      ]),
      "usage": Json::object({
        "prompt_tokens": Json::number(12.0),
        "completion_tokens": Json::number(3.0),
        "total_tokens": Json::number(15.0),
      }),
    })),
    state,
  )

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
      assert_eq(message.usage.input, 12)
      assert_eq(message.usage.output, 3)
      assert_eq(message.usage.total_tokens, 15)
      match message.content[0] {
        Text(text) => assert_eq(text, "hello")
        _ => fail("expected final assistant text")
      }
    }
    _ => fail("expected Done event")
  }
}

test "handle data done marker" {
  let state = OpenAiStreamState::new(openai_test_model())
  let events = parse_openai_sse_line("data: [DONE]", state)
  assert_eq(events.length(), 0)
}
