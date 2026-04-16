test "host runtime from driver delegates to shared driver state" {
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
  )
  let runtime = mom_host_runtime_from_driver(driver)

  runtime.write_event(
    "future.json",
    MomEvent::OneShot({
      channel_id: "slack-acme/C123",
      text: "future",
      at: "2026-04-17T10:00:00+08:00",
    }),
  )
  let step = runtime.sync("2026-04-17T09:00:00+08:00").unwrap()

  match step.result {
    Synced(sync) => assert_eq(sync.sync.changed_plans.length(), 1)
    _ => fail("expected sync result")
  }
  assert_eq(runtime.handle_state().wakeup_due_at_ms, Some(parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap()))
  assert_eq(runtime.list_event_files().length(), 1)
  assert_eq(operations.val.length(), 2)
}

test "host runtime in memory with handle runtime constructs directly" {
  let handle_runtime = InMemoryEventHandleRuntime::new()
  let runtime = mom_host_runtime_in_memory_with_handle_runtime(
    host_test_config(),
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
    "2026-04-16T12:00:00Z",
    handle_runtime,
    event_files=[{
      filename: "daily.json",
      content: "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"daily\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      modified_at: None,
    }],
  )

  let step = runtime.sync("2026-04-17T09:00:00+08:00").unwrap()

  match step.result {
    Synced(sync) => assert_eq(sync.sync.changed_plans.length(), 1)
    _ => fail("expected sync result")
  }
  assert_eq(handle_runtime.snapshot().registered_periodics.length(), 1)
  assert_eq(handle_runtime.snapshot().registered_periodics[0].filename, "daily.json")
  assert_eq(runtime.list_event_files().length(), 1)
}
