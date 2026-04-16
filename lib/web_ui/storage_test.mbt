test "in memory storage backend supports set get prefix and index sorting" {
  let backend = InMemoryStorageBackend::new()
  let metadata_a : SessionMetadata = {
    id: "a",
    title: "Alpha",
    created_at: "2026-04-16T00:00:00.000Z",
    last_modified: "2026-04-16T00:01:00.000Z",
    message_count: 1,
    usage: @ai.Usage::zero(),
    thinking_level: @agent.AgentThinkingLevel::Off,
    preview: "",
  }
  let metadata_b : SessionMetadata = {
    id: "b",
    title: "Beta",
    created_at: "2026-04-16T00:00:00.000Z",
    last_modified: "2026-04-16T00:02:00.000Z",
    message_count: 1,
    usage: @ai.Usage::zero(),
    thinking_level: @agent.AgentThinkingLevel::Off,
    preview: "",
  }

  ignore((backend.backend.set_json)(
    "settings",
    "theme.dark",
    true.to_json(),
  ))
  ignore((backend.backend.set_json)(
    "settings",
    "theme.light",
    false.to_json(),
  ))
  ignore((backend.backend.set_json)(
    "sessions-metadata",
    "a",
    metadata_a.to_json(),
  ))
  ignore((backend.backend.set_json)(
    "sessions-metadata",
    "b",
    metadata_b.to_json(),
  ))

  match (backend.backend.get_json)("settings", "theme.dark") {
    Ok(Some(True)) => ()
    _ => fail("expected stored boolean")
  }

  let prefixed = (backend.backend.keys)("settings", Some("theme.")).unwrap()
  assert_eq(prefixed.length(), 2)

  let sorted = (backend.backend.get_all_from_index)(
    "sessions-metadata",
    "last_modified",
    SortDirection::Desc,
  ).unwrap()
  let first : SessionMetadata = @json.from_json(sorted[0])
  assert_eq(first.id, "b")

  let quota = (backend.backend.get_quota_info)().unwrap()
  assert_true(quota.usage > 0)
}

test "in memory storage backend supports transaction updates across stores" {
  let backend = InMemoryStorageBackend::new()
  ignore((backend.backend.transaction)(
    ["settings", "provider-keys"],
    TransactionMode::ReadWrite,
    fn(transaction) {
      match (transaction.set_json)("settings", "proxy.enabled", true.to_json()) {
        Ok(_) => ()
        Err(message) => return Err(message)
      }
      (transaction.set_json)("provider-keys", "anthropic", "secret".to_json())
    },
  ))

  match (backend.backend.get_json)("settings", "proxy.enabled") {
    Ok(Some(True)) => ()
    _ => fail("expected transaction to write settings store")
  }
  match (backend.backend.get_json)("provider-keys", "anthropic") {
    Ok(Some(String("secret"))) => ()
    _ => fail("expected transaction to write provider-keys store")
  }
}
