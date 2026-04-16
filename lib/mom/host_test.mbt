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

  let result = host.handle_input(Sync("2026-04-17T09:00:00+08:00")).unwrap()

  match result {
    Synced(sync) => {
      assert_eq(sync.sync.changed_plans.length(), 2)
      assert_eq(
        sync.handle_plan.state.wakeup_due_at_ms,
        Some(parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap()),
      )
      assert_eq(sync.handle_plan.state.registered_periodics.length(), 1)
    }
    _ => fail("expected sync result")
  }
  assert_eq(host.list_event_files().length(), 2)
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

  let result = host.handle_input(Message(runner_test_message("hello"))).unwrap()

  match result {
    MessageHandled(turn) =>
      assert_eq(turn.run.assistant_text, "echo:[mario]: hello")
    _ => fail("expected message result")
  }
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
  let queued = host.handle_input(FileChanged(
    "immediate.json",
    parse_mom_timestamp_ms("2026-04-16T12:04:59.900Z").unwrap(),
  )).unwrap()

  match queued {
    FileQueued(pending) => {
      assert_eq(pending.length(), 1)
      assert_eq(pending[0].filename, "immediate.json")
    }
    _ => fail("expected queued file change")
  }

  let result = host.handle_input(Wakeup("2026-04-16T12:05:00.000Z")).unwrap()

  match result {
    Woke(tick) => {
      assert_eq(tick.tick.flushed_files, ["immediate.json"])
      assert_eq(tick.tick.workspace_results.length(), 2)
    }
    _ => fail("expected wakeup result")
  }
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
  ignore(host.handle_input(Sync("2026-04-16T12:05:00.000Z")).unwrap())

  let result = host.handle_input(
    Periodic("daily.json", "2026-04-16T12:05:00.000Z"),
  ).unwrap()

  match result {
    PeriodicDispatched(periodic) =>
      match periodic.dispatch {
        Triggered(run) =>
          assert_eq(
            run.assistant_text,
            "echo:[event]: [EVENT:daily.json:periodic:0 9 * * 1-5] daily",
          )
        _ => fail("expected periodic dispatch")
      }
    _ => fail("expected periodic result")
  }
  assert_eq(host.list_sent_messages().length(), 1)
}

test "mom host result helper skips queued file changes" {
  let host = MomInMemoryHost::new(
    host_test_config(),
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
    "2026-04-16T12:00:00Z",
  )

  let result = host.handle_input(FileChanged("future.json", 1_000UL)).unwrap()

  match mom_host_result_handle_plan(result) {
    None => ()
    Some(_) => fail("expected no handle plan for queued file change")
  }
  assert_eq(host.list_pending_file_changes().length(), 1)
  assert_eq(host.list_pending_file_changes()[0].filename, "future.json")
}
