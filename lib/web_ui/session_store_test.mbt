fn web_ui_user_message(text : String) -> ChatMessage {
  user_message_with_attachments(text)
}

fn web_ui_session_data(
  id : String,
  title : String,
  messages : Array[ChatMessage],
  created_at : String,
  last_modified : String
) -> SessionData {
  {
    id,
    title,
    model: web_ui_test_model(),
    thinking_level: @agent.AgentThinkingLevel::Off,
    messages,
    created_at,
    last_modified,
  }
}

test "generate session title uses first user message" {
  let title = generate_session_title([
    Artifact({
      action: ArtifactAction::Create,
      filename: "demo.html",
      content: None,
      title: None,
      timestamp: "2026-04-16T00:00:00.000Z",
    }),
    web_ui_user_message("Summarize this design review. Then list follow-up tasks."),
    web_ui_assistant_message("ok"),
  ])
  assert_eq(title, "Summarize this design review.")
}

test "should persist session requires user and assistant messages" {
  assert_true(!should_persist_session([web_ui_user_message("only user")]))
  assert_true(!should_persist_session([web_ui_assistant_message("only assistant")]))
  assert_true(should_persist_session([web_ui_user_message("user"), web_ui_assistant_message("assistant")]))
}

test "session metadata derives usage and preview" {
  let data = web_ui_session_data(
    "session-1",
    "",
    [
      web_ui_user_message("Inspect the attached screenshots"),
      web_ui_assistant_message("I found the issue", input=12, output=7),
    ],
    "2026-04-16T00:00:00.000Z",
    "2026-04-16T01:00:00.000Z",
  )

  let metadata = session_metadata_from_data(data)
  assert_eq(metadata.title, "Inspect the attached screenshots")
  assert_eq(metadata.message_count, 2)
  assert_eq(metadata.usage.input, 12)
  assert_eq(metadata.usage.output, 7)
  assert_true(metadata.preview.contains("Inspect the attached screenshots"))
  assert_true(metadata.preview.contains("I found the issue"))
}

test "in memory sessions store saves sorts and updates titles" {
  let store = InMemorySessionsStore::new()
  let alpha = web_ui_session_data(
    "alpha",
    "Alpha title",
    [web_ui_user_message("alpha"), web_ui_assistant_message("done")],
    "2026-04-16T00:00:00.000Z",
    "2026-04-16T00:01:00.000Z",
  )
  let beta = web_ui_session_data(
    "beta",
    "Beta title",
    [web_ui_user_message("beta"), web_ui_assistant_message("done")],
    "2026-04-16T00:00:00.000Z",
    "2026-04-16T00:02:00.000Z",
  )

  store.save(alpha)
  store.save(beta)

  let all_metadata = store.get_all_metadata()
  assert_eq(all_metadata.length(), 2)
  assert_eq(all_metadata[0].id, "beta")
  assert_eq(store.get_latest_session_id(), Some("beta"))

  store.update_title("alpha", "Renamed alpha")
  assert_eq(store.get("alpha").unwrap().title, "Renamed alpha")
  assert_eq(store.get_metadata("alpha").unwrap().title, "Renamed alpha")

  store.delete("beta")
  assert_true(store.get("beta") is None)
  assert_eq(store.get_latest_session_id(), Some("alpha"))
}
