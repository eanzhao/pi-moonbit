fn web_ui_test_model() -> @ai.Model {
  {
    id: "web-test",
    name: "web-test",
    api: @ai.ApiId("mock"),
    provider: @ai.ProviderId("mock"),
    base_url: None,
    reasoning: false,
    input_modalities: [@ai.InputModality::Text, @ai.InputModality::Image],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 8192,
    max_tokens: 2048,
  }
}

fn web_ui_assistant_message(text : String, input? : Int = 0, output? : Int = 0) -> ChatMessage {
  Standard(@ai.Message::Assistant({
    content: [@ai.ContentBlock::Text(text)],
    api: @ai.ApiId("mock"),
    provider: @ai.ProviderId("mock"),
    model: web_ui_test_model().id,
    usage: {
      input,
      output,
      cache_read: 0,
      cache_write: 0,
      total_tokens: input + output,
      cost: {
        input: input.to_double(),
        output: output.to_double(),
        cache_read: 0.0,
        cache_write: 0.0,
        total: input.to_double() + output.to_double(),
      },
    },
    stop_reason: @ai.StopReason::Stop,
    error_message: None,
    timestamp: 0.0,
  }))
}

test "default convert to llm filters artifact messages and converts attachments" {
  let image = image_attachment("image-1", "chart.png", "image/png", 128, "abc")
  let document = document_attachment(
    "doc-1",
    "report.pdf",
    "application/pdf",
    256,
    "def",
    extracted_text=Some("Quarterly numbers"),
  )
  let messages : Array[ChatMessage] = [
    user_message_with_attachments("Analyze the files", attachments=[image, document]),
    Artifact({ action: ArtifactAction::Create, filename: "demo.html", content: None, title: None, timestamp: "2026-04-16T00:00:00.000Z" }),
    web_ui_assistant_message("done"),
  ]

  let converted = default_convert_to_llm(messages)
  assert_eq(converted.length(), 2)
  match converted[0] {
    @ai.Message::User(message) => {
      assert_eq(message.content.length(), 3)
      match message.content[1] {
        @ai.ContentBlock::Image(image_content) => assert_true(image_content.data == "abc")
        _ => fail("expected image content block")
      }
      match message.content[2] {
        @ai.ContentBlock::Text(text) => assert_true(text.contains("[Document: report.pdf]"))
        _ => fail("expected document text block")
      }
    }
    _ => fail("expected converted user message")
  }
}

test "chat message text ignores images and artifacts" {
  let message = user_message_with_attachments(
    "Explain",
    attachments=[image_attachment("img", "photo.png", "image/png", 12, "data")],
  )
  assert_eq(chat_message_text(message), "Explain")
  assert_eq(chat_message_text(Artifact({
    action: ArtifactAction::Delete,
    filename: "old.svg",
    content: None,
    title: None,
    timestamp: "2026-04-16T00:00:00.000Z",
  })), "")
}
