fn mom_user_message(text : String) -> @ai.Message {
  @ai.Message::User({ content: [@ai.ContentBlock::Text(text)] })
}

test "build memory text merges workspace and channel memory" {
  let memory = build_memory_text(
    global_memory=Some("Use tabs."),
    channel_memory=Some("Deploy only after review."),
  )
  assert_true(memory.contains("Global Workspace Memory"))
  assert_true(memory.contains("Channel-Specific Memory"))
  assert_true(memory.contains("Use tabs."))
  assert_true(memory.contains("Deploy only after review."))
}

test "channel message context text includes attachment paths" {
  let text = channel_message_to_context_text({
    id: "1",
    channel_id: "C1",
    timestamp: "2026-04-16T09:00:00.000Z",
    sender: { id: "U1", username: "mario", display_name: None, is_bot: false },
    text: "Inspect this file",
    raw_text: None,
    attachments: [{ filename: "trace.log", local_path: "channels/slack/C1/attachments/trace.log", mime_type: None, size: None }],
    is_mention: true,
    reply_to: None,
    metadata: None,
  })
  assert_true(text.contains("[mario]: Inspect this file"))
  assert_true(text.contains("<attachments>"))
  assert_true(text.contains("trace.log"))
}

test "sync channel log appends unseen non bot messages in timestamp order" {
  let session = @coding_agent.SessionManager::new(session_id="mom-sync")
  ignore(session.append_message(mom_user_message("[mario]: already synced"), timestamp="2026-04-16T08:59:00.000Z"))

  let synced = sync_channel_log_to_session_manager(
    session,
    [
      mom_test_message("bot-1", "C1", "2026-04-16T09:03:00.000Z", "ignore me", is_bot=true),
      mom_test_message("2", "C1", "2026-04-16T09:02:00.000Z", "second"),
      mom_test_message("1", "C1", "2026-04-16T09:01:00.000Z", "already synced"),
      mom_test_message("3", "C1", "2026-04-16T09:04:00.000Z", "current"),
    ],
    exclude_message_id=Some("3"),
  )

  assert_eq(synced, 1)
  let transcript = session.build_transcript_messages()
  assert_eq(transcript.length(), 2)
  match transcript[1] {
    @ai.Message::User(message) =>
      match message.content[0] {
        @ai.ContentBlock::Text(text) => assert_eq(text, "[mario]: second")
        _ => fail("expected text block")
      }
    _ => fail("expected user message")
  }
}
