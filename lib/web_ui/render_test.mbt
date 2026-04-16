fn render_test_assistant_message() -> @ai.Message {
  @ai.Message::Assistant({
    content: [
      @ai.ContentBlock::Text("Need data"),
      @ai.ContentBlock::ToolCall({
        id: "call_1",
        name: "lookup_weather",
        arguments: Json::object({ "city": Json::string("Paris") }),
      }),
    ],
    api: @ai.ApiId("mock"),
    provider: @ai.ProviderId("mock"),
    model: "gpt-test",
    usage: {
      input: 12,
      output: 3,
      cache_read: 0,
      cache_write: 0,
      total_tokens: 15,
      cost: {
        input: 0.0,
        output: 0.0,
        cache_read: 0.0,
        cache_write: 0.0,
        total: 0.0,
      },
    },
    stop_reason: @ai.StopReason::ToolUse,
    error_message: None,
    timestamp: 123.0,
  })
}

test "chat_message_to_renderable basic conversion" {
  let message = user_message_with_attachments(
    "hello",
    attachments=[document_attachment(
      "doc-1",
      "notes.txt",
      "text/plain",
      8,
      "ZGF0YQ==",
      extracted_text=Some("notes"),
    )],
    timestamp=42.0,
  )
  let renderable = chat_message_to_renderable(message, is_streaming=true)

  assert_eq(renderable.role, "user")
  assert_eq(renderable.timestamp, 42L)
  assert_eq(renderable.model, "")
  match renderable.usage {
    None => ()
    Some(_) => fail("expected no usage")
  }
  assert_true(renderable.is_streaming)
  assert_eq(renderable.content.length(), 2)

  match renderable.content[0] {
    RenderableBlock::Text(text) => assert_eq(text, "hello")
    _ => fail("expected text block")
  }
  match renderable.content[1] {
    RenderableBlock::Attachment(attachment) => {
      assert_eq(attachment.name, "notes.txt")
      assert_eq(attachment.mime_type, "text/plain")
      assert_true(attachment.url.has_prefix("data:text/plain;base64,"))
    }
    _ => fail("expected attachment block")
  }
}

test "ai_message_to_renderable basic conversion" {
  let renderable = ai_message_to_renderable(render_test_assistant_message())

  assert_eq(renderable.role, "assistant")
  assert_eq(renderable.timestamp, 123L)
  assert_eq(renderable.model, "gpt-test")
  assert_true(!renderable.is_error)
  assert_eq(renderable.content.length(), 2)

  match renderable.usage {
    Some(usage) => {
      assert_eq(usage.input_tokens, 12)
      assert_eq(usage.output_tokens, 3)
    }
    None => fail("expected usage")
  }

  match renderable.content[0] {
    RenderableBlock::Text(text) => assert_eq(text, "Need data")
    _ => fail("expected text block")
  }
  match renderable.content[1] {
    RenderableBlock::ToolCall(tool_call) => {
      assert_eq(tool_call.id, "call_1")
      assert_eq(tool_call.name, "lookup_weather")
      assert_true(tool_call.arguments.contains("\"city\""))
      match tool_call.status {
        ToolCallStatus::Pending => ()
        _ => fail("expected pending tool call")
      }
    }
    _ => fail("expected tool call block")
  }
}
