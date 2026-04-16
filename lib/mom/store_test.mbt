fn mom_test_message(
  id : String,
  channel_id : String,
  timestamp : String,
  text : String,
  is_bot? : Bool = false
) -> ChannelMessage {
  {
    id,
    channel_id,
    timestamp,
    sender: {
      id: if is_bot { "bot" } else { "U1" },
      username: if is_bot { "mom" } else { "mario" },
      display_name: None,
      is_bot,
    },
    text,
    raw_text: None,
    attachments: [],
    is_mention: false,
    reply_to: None,
    metadata: None,
  }
}

test "workspace paths namespace channels by adapter" {
  let base = "/workspace"
  assert_eq(workspace_global_memory_path(base), "/workspace/MEMORY.md")
  assert_eq(workspace_events_dir(base), "/workspace/events")
  assert_eq(event_filename_in_dir("/workspace/events", "daily.json"), Some("daily.json"))
  assert_eq(
    event_filename_in_dir("/workspace/events", "/workspace/events/nested/daily.json"),
    Some("nested/daily.json"),
  )
  assert_eq(workspace_event_filename(base, "/workspace/events/daily.json"), Some("daily.json"))
  assert_eq(workspace_event_filename(base, "/tmp/daily.json"), None)
  assert_eq(workspace_channel_dir(base, "slack-acme", "C123"), "/workspace/channels/slack-acme/C123")
  assert_eq(workspace_channel_log_path(base, "slack-acme", "C123"), "/workspace/channels/slack-acme/C123/log.jsonl")
  assert_eq(qualified_channel_id("slack-acme", "C123"), "slack-acme/C123")
  assert_eq(parse_qualified_channel_id("slack-acme/C123"), Some(("slack-acme", "C123")))
}

test "log jsonl round trips modern and legacy message shapes" {
  let message : ChannelMessage = {
    id: "1734.1",
    channel_id: "C123",
    timestamp: "2026-04-16T09:00:00.000Z",
    sender: { id: "U1", username: "mario", display_name: Some("Mario"), is_bot: false },
    text: "hello",
    raw_text: Some("<@Ubot> hello"),
    attachments: [{ filename: "spec.txt", local_path: "attachments/spec.txt", mime_type: Some("text/plain"), size: Some(12) }],
    is_mention: true,
    reply_to: Some("thread-1"),
    metadata: Some(Json::object({ "source": Json::string("slack") })),
  }

  let jsonl = serialize_log_jsonl([message])
  let parsed = parse_log_jsonl(jsonl, "C123").unwrap()
  assert_eq(parsed.length(), 1)
  assert_true(parsed[0] == message)

  let legacy = "{\"ts\":\"1734.2\",\"date\":\"2026-04-16T09:01:00.000Z\",\"user\":\"U2\",\"userName\":\"alice\",\"displayName\":\"Alice\",\"text\":\"legacy\",\"attachments\":[{\"original\":\"a.txt\",\"local\":\"C123/attachments/a.txt\"}],\"isBot\":false}\n"
  let legacy_parsed = parse_log_jsonl(legacy, "C123").unwrap()
  assert_eq(legacy_parsed[0].sender.username, "alice")
  assert_eq(legacy_parsed[0].attachments[0].filename, "a.txt")
  assert_eq(legacy_parsed[0].channel_id, "C123")
}

test "in memory channel store deduplicates and sorts metadata" {
  let store = InMemoryChannelStore::new()
  assert_true(store.append_message("slack-acme", mom_test_message("1", "C1", "2026-04-16T09:00:00.000Z", "alpha")))
  assert_true(store.append_message("slack-acme", mom_test_message("2", "C2", "2026-04-16T10:00:00.000Z", "beta")))
  assert_true(!store.append_message("slack-acme", mom_test_message("2", "C2", "2026-04-16T10:00:00.000Z", "beta")))

  let metadata = store.list_metadata()
  assert_eq(metadata.length(), 2)
  assert_eq(metadata[0].channel_id, "C2")
  assert_eq(metadata[0].preview, "beta")
  assert_eq(store.get_metadata("slack-acme", "C1").unwrap().message_count, 1)
}
