fn host_test_config() -> MomAgentConfig {
  MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    runner_test_model(),
    runner_test_agent_runtime(),
  )
}

test "in-memory host sync tracks event files and handle state" {
  let host = MomInMemoryHost::new(
    host_test_config(),
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
    "2026-04-16T12:00:00Z",
    event_files=[
      {
        filename: "future.json",
        content: "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
        modified_at: None,
      },
      {
        filename: "daily.json",
        content: "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"daily\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
        modified_at: None,
      },
    ],
  )

  let result = host.sync("2026-04-17T09:00:00+08:00").unwrap()

  assert_eq(result.sync.changed_plans.length(), 2)
  assert_eq(host.list_event_files().length(), 2)
  assert_eq(
    host.handle_state().wakeup_due_at_ms,
    Some(parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap()),
  )
  assert_eq(host.handle_state().registered_periodics.length(), 1)
}

test "in-memory host handle_message refreshes future timer state" {
  let host = MomInMemoryHost::new(
    host_test_config(),
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
    "2026-04-16T12:00:00Z",
  )
  host.write_event(
    "future.json",
    MomEvent::OneShot({
      channel_id: "slack-acme/C123",
      text: "future",
      at: "2026-04-17T10:00:00+08:00",
    }),
  )

  let result = host.handle_message(runner_test_message("hello")).unwrap()

  assert_eq(result.run.assistant_text, "echo:[mario]: hello")
  assert_eq(host.list_sent_messages().length(), 1)
  assert_eq(
    host.handle_state().wakeup_due_at_ms,
    Some(parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap()),
  )
}

test "in-memory host tick dispatches immediate event and keeps future file" {
  let host = MomInMemoryHost::new(
    host_test_config(),
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
    "2026-04-16T12:00:00Z",
    debounce_ms=100UL,
  )
  host.write_event(
    "immediate.json",
    MomEvent::Immediate({ channel_id: "slack-acme/C123", text: "ping" }),
    modified_at=Some("2026-04-16T12:04:59.950Z"),
  )
  host.write_event(
    "future.json",
    MomEvent::OneShot({
      channel_id: "slack-acme/C123",
      text: "future",
      at: "2026-04-17T10:00:00+08:00",
    }),
  )
  host.note_file_change(
    "immediate.json",
    parse_mom_timestamp_ms("2026-04-16T12:04:59.900Z").unwrap(),
  )

  let result = host.tick("2026-04-16T12:05:00.000Z").unwrap()

  assert_eq(result.tick.flushed_files, ["immediate.json"])
  assert_eq(result.tick.workspace_results.length(), 2)
  assert_eq(host.list_sent_messages().length(), 1)
  assert_eq(host.list_event_files().length(), 1)
  assert_eq(host.list_event_files()[0].filename, "future.json")
}

test "in-memory host dispatch_periodic routes through registered event" {
  let host = MomInMemoryHost::new(
    host_test_config(),
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
    "2026-04-16T12:00:00Z",
  )
  host.write_event(
    "daily.json",
    MomEvent::Periodic({
      channel_id: "slack-acme/C123",
      text: "daily",
      schedule: "0 9 * * 1-5",
      timezone: "Asia/Singapore",
    }),
  )
  ignore(host.sync("2026-04-16T12:05:00.000Z").unwrap())

  let result = host.dispatch_periodic("daily.json", "2026-04-16T12:05:00.000Z").unwrap()

  match result.dispatch {
    Triggered(run) =>
      assert_eq(
        run.assistant_text,
        "echo:[event]: [EVENT:daily.json:periodic:0 9 * * 1-5] daily",
      )
    _ => fail("expected periodic dispatch")
  }
  assert_eq(host.list_sent_messages().length(), 1)
}
