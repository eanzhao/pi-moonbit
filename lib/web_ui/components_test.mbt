test "attachment tile renders preview and delete action" {
  let tile = AttachmentTileView::new(
    image_attachment("img-1", "photo.png", "image/png", 1536, "abc123"),
    show_delete=true,
  )
  let rendered = render_component_html(tile)

  assert_true(rendered.contains("attachment-image"))
  assert_true(rendered.contains("data:image/png;base64,abc123"))
  assert_true(rendered.contains("data-action=\"delete-attachment\""))
}

test "custom provider card renders status and actions" {
  let provider : CustomProvider = {
    id: "provider-1",
    name: "My Ollama",
    provider_type: CustomProviderType::AutoDiscovery(AutoDiscoveryProviderType::Ollama),
    base_url: "http://localhost:11434",
    api_key: None,
    models: None,
  }
  let card = CustomProviderCardView::new(
    provider,
    status=Some({ model_count: 3, state: ProviderConnectionState::Connected }),
    show_refresh=true,
  )
  let rendered = render_component_html(card)

  assert_true(rendered.contains("My Ollama"))
  assert_true(rendered.contains("3 models"))
  assert_true(rendered.contains("refresh-provider"))
  assert_true(rendered.contains("http://localhost:11434"))
}

test "message list renders transcript and skips artifact messages" {
  let messages : Array[ChatMessage] = [
    user_message_with_attachments(
      "Analyze this",
      attachments=[document_attachment(
        "doc-1",
        "report.pdf",
        "application/pdf",
        256,
        "base64",
        extracted_text=Some("Report body"),
      )],
    ),
    Artifact({
      action: ArtifactAction::Create,
      filename: "demo.html",
      content: Some("<div>artifact</div>"),
      title: Some("artifact"),
      timestamp: "2026-04-16T00:00:00.000Z",
    }),
    web_ui_assistant_message("done", input=10, output=4),
    Standard(@ai.Message::ToolResult({
      content: [@ai.ContentBlock::Text("tool output")],
      tool_call_id: "call-1",
      tool_name: "bash",
      error: false,
    })),
  ]
  let rendered = render_component_html(MessageListView::new(messages, is_streaming=true))

  assert_true(rendered.contains("Analyze this"))
  assert_true(rendered.contains("Report body"))
  assert_true(rendered.contains("done"))
  assert_true(rendered.contains("bash"))
  assert_true(rendered.contains("Streaming..."))
  assert_true(!rendered.contains("artifact</div>"))
}

test "session list and model selector render summaries" {
  let session = session_metadata_from_data(web_ui_session_data(
    "session-1",
    "Demo session",
    [web_ui_user_message("hello"), web_ui_assistant_message("world", input=1200, output=40)],
    "2026-04-15T00:00:00.000Z",
    "2026-04-16T00:00:00.000Z",
  ))
  let session_html = render_component_html(SessionListView::new([session], "2026-04-16T12:00:00.000Z"))
  assert_true(session_html.contains("Demo session"))
  assert_true(session_html.contains("Today"))
  assert_true(session_html.contains("2 messages"))

  let current = web_ui_test_model()
  let selector_html = render_component_html(ModelSelectorView::new([
    { provider: "mock", model: current },
    {
      provider: "anthropic",
      model: {
        id: "claude-sonnet",
        name: "Claude Sonnet",
        api: @ai.api_anthropic_messages,
        provider: @ai.ProviderId("anthropic"),
        base_url: Some("https://api.anthropic.com"),
        reasoning: true,
        input_modalities: [@ai.InputModality::Text, @ai.InputModality::Image],
        cost: { input: 3.0, output: 15.0, cache_read: 0.3, cache_write: 3.75 },
        context_window: 200000,
        max_tokens: 8192,
      },
    },
  ], current_model=Some(current)))
  assert_true(selector_html.contains("current"))
  assert_true(selector_html.contains("thinking"))
  assert_true(selector_html.contains("vision"))
}
