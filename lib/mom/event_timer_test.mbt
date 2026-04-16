test "one-shot timer registry registers and flushes due timers in order" {
  let registry = MomOneShotTimerRegistry::new()

  registry.register({
    filename: "b.json",
    event: {
      channel_id: "slack-acme/C123",
      text: "b",
      at: "2026-04-17T10:05:00+08:00",
    },
  }).unwrap()
  registry.register({
    filename: "a.json",
    event: {
      channel_id: "slack-acme/C123",
      text: "a",
      at: "2026-04-17T10:00:00+08:00",
    },
  }).unwrap()

  assert_true(registry.next_due_at_ms() is Some(_))

  let due = registry.flush_due(parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap())
  assert_eq(due.length(), 1)
  assert_eq(due[0].filename, "a.json")
  assert_eq(registry.list_timers().length(), 1)
  assert_eq(registry.list_timers()[0].filename, "b.json")
}

test "one-shot timer registry apply_sync adds removes and replaces timers" {
  let registry = MomOneShotTimerRegistry::new()

  registry.apply_sync({
    changed_plans: [],
    added_one_shots: [
      {
        filename: "reminder.json",
        event: {
          channel_id: "slack-acme/C123",
          text: "remind",
          at: "2026-04-17T10:00:00+08:00",
        },
      },
    ],
    removed_one_shots: [],
    added_periodics: [],
    removed_periodics: [],
  }).unwrap()
  assert_eq(registry.list_timers().length(), 1)

  registry.apply_sync({
    changed_plans: [],
    added_one_shots: [
      {
        filename: "reminder.json",
        event: {
          channel_id: "slack-acme/C123",
          text: "remind",
          at: "2026-04-17T11:00:00+08:00",
        },
      },
    ],
    removed_one_shots: [],
    added_periodics: [],
    removed_periodics: [],
  }).unwrap()
  assert_eq(registry.list_timers().length(), 1)
  assert_eq(registry.list_timers()[0].event.at, "2026-04-17T11:00:00+08:00")

  registry.apply_sync({
    changed_plans: [],
    added_one_shots: [],
    removed_one_shots: [
      {
        filename: "reminder.json",
        event: {
          channel_id: "slack-acme/C123",
          text: "remind",
          at: "2026-04-17T11:00:00+08:00",
        },
      },
    ],
    added_periodics: [],
    removed_periodics: [],
  }).unwrap()
  assert_eq(registry.list_timers().length(), 0)
}

test "one-shot timer registry rejects invalid timestamps" {
  let registry = MomOneShotTimerRegistry::new()

  let result = registry.register({
    filename: "bad.json",
    event: {
      channel_id: "slack-acme/C123",
      text: "bad",
      at: "2026-04-17T10:00:00",
    },
  })

  assert_true(result is Err(_))
}
