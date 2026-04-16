struct TestHandleWorkspace {
  files : Array[(String, String, String?)]
}

struct FailingHandleRuntime {
  fail_step : String
}

fn test_event_handle_runtime(
  files : Array[(String, String, String?)]
) -> MomEventWorkspaceRuntime {
  let workspace : Ref[TestHandleWorkspace] = Ref::new({ files: files })
  MomEventWorkspaceRuntime::new(
    fn(path) {
      for item in workspace.val.files {
        let (file_path, content, _modified_at) = item
        if file_path == path {
          return Ok(content)
        }
      }
      Err("missing file: " + path)
    },
    fn(dir) {
      let prefix = if dir.has_suffix("/") { dir } else { dir + "/" }
      let listed : Array[String] = []
      for item in workspace.val.files {
        let (path, _content, _modified_at) = item
        if path.has_prefix(prefix) {
          listed.push(path)
        }
      }
      Ok(listed)
    },
    read_modified_at=fn(path) {
      for item in workspace.val.files {
        let (file_path, _content, modified_at) = item
        if file_path == path {
          return Ok(modified_at)
        }
      }
      Err("missing file: " + path)
    },
  )
}

test "event handle plan tracks watch dir and wakeup timer" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z", debounce_ms=100UL)

  loop_.note_file_change("pending.json", 1_000UL)
  let plan = loop_.plan_handles(MomEventHandleState::new())

  assert_true(plan.has_changes())
  assert_true(plan.watch_changed)
  assert_true(plan.wakeup_changed)
  assert_eq(plan.state.watched_dir, Some("/workspace/events"))
  assert_eq(plan.state.wakeup_due_at_ms, Some(1_100UL))
  assert_eq(plan.added_periodics.length(), 0)
  assert_eq(plan.removed_periodics.length(), 0)
}

test "event handle plan diffs periodic registrations against current handles" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z")
  let runtime = test_event_handle_runtime([
    (
      "/workspace/events/future.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
    (
      "/workspace/events/daily.json",
      "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"daily\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      None,
    ),
  ])
  ignore(loop_.sync_workspace(runtime, "2026-04-17T09:00:00+08:00").unwrap())

  let current = MomEventHandleState::new(
    watched_dir=Some("/workspace/events"),
    wakeup_due_at_ms=Some(1UL),
    registered_periodics=[{
      filename: "old.json",
      event: {
        channel_id: "slack-acme/C123",
        text: "old",
        schedule: "0 1 * * *",
        timezone: "Asia/Singapore",
      },
    }],
  )
  let plan = loop_.plan_handles(current)

  assert_false(plan.watch_changed)
  assert_true(plan.wakeup_changed)
  assert_eq(
    plan.state.wakeup_due_at_ms,
    Some(parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap()),
  )
  assert_eq(plan.added_periodics.length(), 1)
  assert_eq(plan.added_periodics[0].filename, "daily.json")
  assert_eq(plan.removed_periodics.length(), 1)
  assert_eq(plan.removed_periodics[0].filename, "old.json")
}

test "event handle plan is stable when handles already match desired state" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z", debounce_ms=100UL)

  loop_.note_file_change("pending.json", 1_000UL)
  let desired = loop_.desired_handle_state()
  let plan = loop_.plan_handles(desired)

  assert_false(plan.has_changes())
  assert_false(plan.watch_changed)
  assert_false(plan.wakeup_changed)
  assert_eq(plan.added_periodics.length(), 0)
  assert_eq(plan.removed_periodics.length(), 0)
}

test "event handle plan operations follow host apply order" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z")
  let runtime = test_event_handle_runtime([
    (
      "/workspace/events/future.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
    (
      "/workspace/events/daily.json",
      "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"daily\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      None,
    ),
  ])
  ignore(loop_.sync_workspace(runtime, "2026-04-17T09:00:00+08:00").unwrap())

  let current = MomEventHandleState::new(
    watched_dir=Some("/workspace/events"),
    wakeup_due_at_ms=Some(1UL),
    registered_periodics=[{
      filename: "old.json",
      event: {
        channel_id: "slack-acme/C123",
        text: "old",
        schedule: "0 1 * * *",
        timezone: "Asia/Singapore",
      },
    }],
  )
  let plan = loop_.plan_handles(current)

  let operations = plan.operations()
  assert_eq(operations.length(), 3)
  match operations[0] {
    SetWakeup(Some(value)) =>
      assert_eq(value, parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap())
    _ => fail("expected wakeup update")
  }
  match operations[1] {
    RemovePeriodic(filename) => assert_eq(filename, "old.json")
    _ => fail("expected periodic removal")
  }
  match operations[2] {
    RegisterPeriodic(entry) => {
      assert_eq(entry.filename, "daily.json")
      assert_eq(entry.event.schedule, "0 9 * * 1-5")
    }
    _ => fail("expected periodic registration")
  }
}

test "apply_event_handle_plan updates in-memory runtime state" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z", debounce_ms=100UL)

  loop_.note_file_change("pending.json", 1_000UL)
  let plan = loop_.plan_handles(MomEventHandleState::new())
  let runtime = InMemoryEventHandleRuntime::new()
  let next_state = apply_event_handle_plan(runtime, plan).unwrap()

  assert_eq(next_state.watched_dir, plan.state.watched_dir)
  assert_eq(next_state.wakeup_due_at_ms, plan.state.wakeup_due_at_ms)
  assert_eq(next_state.registered_periodics.length(), plan.state.registered_periodics.length())

  let snapshot = runtime.snapshot()
  assert_eq(snapshot.watched_dir, plan.state.watched_dir)
  assert_eq(snapshot.wakeup_due_at_ms, plan.state.wakeup_due_at_ms)
  assert_eq(snapshot.registered_periodics.length(), plan.state.registered_periodics.length())

  let operations = runtime.list_operations()
  assert_eq(operations.length(), 2)
  match operations[0] {
    SetWatchDir(Some(path)) => assert_eq(path, "/workspace/events")
    _ => fail("expected watch dir update")
  }
  match operations[1] {
    SetWakeup(Some(value)) => assert_eq(value, 1_100UL)
    _ => fail("expected wakeup update")
  }
}

test "apply_event_handle_plan propagates runtime errors" {
  let runtime = FailingHandleRuntime::{ fail_step: "wakeup" }
  let plan : MomEventHandlePlan = {
    state: MomEventHandleState::new(
      watched_dir=Some("/workspace/events"),
      wakeup_due_at_ms=Some(123UL),
    ),
    watch_changed: true,
    wakeup_changed: true,
    added_periodics: [],
    removed_periodics: [],
  }

  match apply_event_handle_plan(runtime, plan) {
    Err(message) => assert_eq(message, "wakeup failed")
    Ok(_) => fail("expected runtime failure")
  }
}

pub impl MomEventHandleRuntime for FailingHandleRuntime with set_watch_dir(self, _watched_dir) {
  if self.fail_step == "watch" {
    Err("watch failed")
  } else {
    Ok(())
  }
}

pub impl MomEventHandleRuntime for FailingHandleRuntime with set_wakeup_due_at_ms(self, _due_at_ms) {
  if self.fail_step == "wakeup" {
    Err("wakeup failed")
  } else {
    Ok(())
  }
}

pub impl MomEventHandleRuntime for FailingHandleRuntime with register_periodic(self, _entry) {
  if self.fail_step == "register" {
    Err("register failed")
  } else {
    Ok(())
  }
}

pub impl MomEventHandleRuntime for FailingHandleRuntime with remove_periodic(self, _filename) {
  if self.fail_step == "remove" {
    Err("remove failed")
  } else {
    Ok(())
  }
}
