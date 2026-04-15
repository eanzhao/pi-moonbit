fn coding_agent_test_model() -> @ai.Model {
  {
    id: "mock",
    name: "mock",
    api: @ai.api_openai_responses,
    provider: @ai.provider_openai,
    base_url: None,
    reasoning: false,
    input_modalities: [@ai.InputModality::Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 8192,
    max_tokens: 2048,
  }
}

fn coding_agent_user_message(text : String) -> @ai.Message {
  @ai.Message::User({ content: [@ai.ContentBlock::Text(text)] })
}

fn coding_agent_assistant_message(text : String) -> @ai.Message {
  @ai.Message::Assistant({
    content: [@ai.ContentBlock::Text(text)],
    api: @ai.api_openai_responses,
    provider: @ai.provider_openai,
    model: "mock",
    usage: @ai.Usage::zero(),
    stop_reason: @ai.StopReason::Stop,
    error_message: None,
    timestamp: 0.0,
  })
}

fn coding_agent_message_text(message : @ai.Message) -> String {
  match message {
    @ai.Message::User(user_message) =>
      match user_message.content[0] {
        @ai.ContentBlock::Text(text) => text
        _ => abort("expected user text block")
      }
    @ai.Message::Assistant(assistant_message) =>
      match assistant_message.content[0] {
        @ai.ContentBlock::Text(text) => text
        _ => abort("expected assistant text block")
      }
    @ai.Message::ToolResult(tool_result_message) =>
      match tool_result_message.content[0] {
        @ai.ContentBlock::Text(text) => text
        _ => abort("expected tool result text block")
      }
  }
}

test "session manager builds branch context with summary and custom message" {
  let session = SessionManager::new(session_id="branch-session")
  let root_id = session.append_message(coding_agent_user_message("root"))
  let _ = session.append_message(coding_agent_assistant_message("first path"))
  let previous_leaf = session.get_leaf_id()
  assert_true(session.branch(Some(root_id)) is Ok(_))
  let _ = session.append_branch_summary("old branch summary", from_id=previous_leaf)
  let _ = session.append_custom_message(
    "note",
    [@ai.ContentBlock::Text("remember the branch")],
  )

  let context = session.build_session_context()
  assert_eq(context.messages.length(), 3)
  assert_eq(coding_agent_message_text(context.messages[0]), "root")
  assert_true(coding_agent_message_text(context.messages[1]).contains("old branch summary"))
  assert_eq(coding_agent_message_text(context.messages[2]), "remember the branch")
}

test "session manager emits compaction summary and kept messages" {
  let session = SessionManager::new(session_id="compaction-session")
  let _ = session.append_message(coding_agent_user_message("before"))
  let _ = session.append_message(coding_agent_assistant_message("before-assistant"))
  let keep_id = session.append_message(coding_agent_user_message("after"))
  let _ = session.append_message(coding_agent_assistant_message("after-assistant"))
  let _ = session.append_compaction("compressed history", keep_id, 123)

  let context = session.build_session_context()
  assert_eq(context.messages.length(), 3)
  assert_true(coding_agent_message_text(context.messages[0]).contains("compressed history"))
  assert_eq(coding_agent_message_text(context.messages[1]), "after")
  assert_eq(coding_agent_message_text(context.messages[2]), "after-assistant")
}

test "session manager tracks model and thinking changes in context" {
  let session = SessionManager::new()
  let model = coding_agent_test_model()
  let _ = session.append_model_change(model)
  let _ = session.append_thinking_level_change(@agent.AgentThinkingLevel::High)

  let context = session.build_session_context()
  assert_true(context.model is Some(_))
  match context.thinking_level {
    Some(level) => assert_true(level == @agent.AgentThinkingLevel::High)
    None => fail("expected saved thinking level")
  }
}
