test "host driver sync and periodic share host state" {
  let host = MomInMemoryHost::new(
    host_test_config(),
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
    "2026-04-16T12:00:00Z",
    event_files=[{
      filename: "daily.json",
      content: "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"daily\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      modified_at: None,
    }],
  )
  let operations : Ref[Array[MomEventHandleOp]] = Ref::new([])
  let driver = MomHostDriver::new(
    host,
    MomHostCallbacks::new(
      fn(watched_dir) {
        operations.val.push(SetWatchDir(watched_dir))
        Ok(())
      },
      fn(due_at_ms) {
        operations.val.push(SetWakeup(due_at_ms))
        Ok(())
      },
      fn(entry) {
        operations.val.push(RegisterPeriodic(entry))
        Ok(())
      },
      fn(filename) {
        operations.val.push(RemovePeriodic(filename))
        Ok(())
      },
    ),
  )

  let sync_step = driver.sync("2026-04-17T09:00:00+08:00").unwrap()
  match sync_step.result {
    Synced(sync) => assert_eq(sync.sync.changed_plans.length(), 1)
    _ => fail("expected sync result")
  }
  assert_eq(driver.handle_state().registered_periodics.length(), 1)
  assert_eq(operations.val.length(), 2)

  let periodic_step = driver.dispatch_periodic(
    "daily.json",
    "2026-04-17T09:00:00+08:00",
  ).unwrap()
  match periodic_step.result {
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
  assert_eq(driver.list_sent_messages().length(), 1)
}

test "host driver file_changed and wakeup reuse same host instance" {
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
  let driver = MomHostDriver::new(
    host,
    MomHostCallbacks::new(
      fn(_watched_dir) { Ok(()) },
      fn(_due_at_ms) { Ok(()) },
      fn(_entry) { Ok(()) },
      fn(_filename) { Ok(()) },
    ),
  )

  let queued = driver.file_changed(
    "immediate.json",
    parse_mom_timestamp_ms("2026-04-16T12:04:59.900Z").unwrap(),
  ).unwrap()
  match queued.result {
    FileQueued(pending) => {
      assert_eq(pending.length(), 1)
      assert_eq(pending[0].filename, "immediate.json")
    }
    _ => fail("expected queued file change")
  }
  assert_eq(driver.list_pending_file_changes().length(), 1)

  let wake_step = driver.wakeup("2026-04-16T12:05:00.000Z").unwrap()
  match wake_step.result {
    Woke(tick) => assert_eq(tick.tick.flushed_files, ["immediate.json"])
    _ => fail("expected wakeup result")
  }
  assert_eq(driver.list_sent_messages().length(), 1)
  assert_eq(driver.list_event_files().length(), 1)
  assert_eq(driver.list_event_files()[0].filename, "future.json")
}

test "host driver new_in_memory builds usable driver directly" {
  let operations : Ref[Array[MomEventHandleOp]] = Ref::new([])
  let driver = MomHostDriver::new_in_memory(
    host_test_config(),
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
    "2026-04-16T12:00:00Z",
    MomHostCallbacks::new(
      fn(watched_dir) {
        operations.val.push(SetWatchDir(watched_dir))
        Ok(())
      },
      fn(due_at_ms) {
        operations.val.push(SetWakeup(due_at_ms))
        Ok(())
      },
      fn(entry) {
        operations.val.push(RegisterPeriodic(entry))
        Ok(())
      },
      fn(filename) {
        operations.val.push(RemovePeriodic(filename))
        Ok(())
      },
    ),
    event_files=[{
      filename: "daily.json",
      content: "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"daily\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      modified_at: None,
    }],
  )

  let step = driver.sync("2026-04-17T09:00:00+08:00").unwrap()

  match step.result {
    Synced(sync) => assert_eq(sync.sync.changed_plans.length(), 1)
    _ => fail("expected sync result")
  }
  assert_eq(operations.val.length(), 2)
  assert_eq(driver.handle_state().registered_periodics.length(), 1)
}

test "host driver exposes event workspace mutation helpers" {
  let driver = MomHostDriver::new_in_memory(
    host_test_config(),
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
    "2026-04-16T12:00:00Z",
    MomHostCallbacks::new(
      fn(_watched_dir) { Ok(()) },
      fn(_due_at_ms) { Ok(()) },
      fn(_entry) { Ok(()) },
      fn(_filename) { Ok(()) },
    ),
  )

  driver.write_event(
    "future.json",
    MomEvent::OneShot({
      channel_id: "slack-acme/C123",
      text: "future",
      at: "2026-04-17T10:00:00+08:00",
    }),
  )
  ignore(driver.file_changed("future.json", 1_000UL).unwrap())

  assert_eq(driver.list_event_files().length(), 1)
  assert_eq(driver.list_pending_file_changes().length(), 1)
  assert_true(driver.clear_file_change("future.json"))
  assert_eq(driver.list_pending_file_changes().length(), 0)
  assert_true(driver.delete_event_file("future.json"))
  assert_eq(driver.list_event_files().length(), 0)
}

test "run mom host input with handle runtime bridges directly" {
  let host = MomInMemoryHost::new(
    host_test_config(),
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
    "2026-04-16T12:00:00Z",
    event_files=[{
      filename: "future.json",
      content: "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      modified_at: None,
    }],
  )
  let runtime = InMemoryEventHandleRuntime::new()

  let step = run_mom_host_input_with_handle_runtime(
    host,
    Sync("2026-04-17T09:00:00+08:00"),
    runtime,
  ).unwrap()

  match step.result {
    Synced(sync) => assert_eq(sync.sync.changed_plans.length(), 1)
    _ => fail("expected sync result")
  }
  assert_eq(runtime.snapshot().wakeup_due_at_ms, Some(parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap()))
  assert_eq(runtime.list_operations().length(), 2)
}

test "host driver can be built directly from handle runtime" {
  let runtime = InMemoryEventHandleRuntime::new()
  let driver = MomHostDriver::new_in_memory_with_handle_runtime(
    host_test_config(),
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
    "2026-04-16T12:00:00Z",
    runtime,
    event_files=[{
      filename: "daily.json",
      content: "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"daily\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      modified_at: None,
    }],
  )

  let step = driver.sync("2026-04-17T09:00:00+08:00").unwrap()

  match step.result {
    Synced(sync) => assert_eq(sync.sync.changed_plans.length(), 1)
    _ => fail("expected sync result")
  }
  assert_eq(runtime.snapshot().registered_periodics.length(), 1)
  assert_eq(runtime.snapshot().registered_periodics[0].filename, "daily.json")
}
