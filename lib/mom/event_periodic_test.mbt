test "periodic registry apply_sync adds removes and replaces entries" {
  let registry = MomPeriodicRegistry::new()

  registry.apply_sync({
    changed_plans: [],
    added_one_shots: [],
    removed_one_shots: [],
    added_periodics: [
      {
        filename: "daily.json",
        event: {
          channel_id: "slack-acme/C123",
          text: "daily",
          schedule: "0 9 * * 1-5",
          timezone: "Asia/Singapore",
        },
      },
    ],
    removed_periodics: [],
  })
  assert_eq(registry.list_entries().length(), 1)
  assert_eq(registry.list_entries()[0].event.schedule, "0 9 * * 1-5")

  registry.apply_sync({
    changed_plans: [],
    added_one_shots: [],
    removed_one_shots: [],
    added_periodics: [
      {
        filename: "daily.json",
        event: {
          channel_id: "slack-acme/C123",
          text: "daily",
          schedule: "0 10 * * 1-5",
          timezone: "Asia/Singapore",
        },
      },
      {
        filename: "weekly.json",
        event: {
          channel_id: "slack-acme/C123",
          text: "weekly",
          schedule: "0 9 * * 1",
          timezone: "Asia/Singapore",
        },
      },
    ],
    removed_periodics: [],
  })
  let entries = registry.list_entries()
  assert_eq(entries.length(), 2)
  assert_true(periodic_test_has_entry(entries, "daily.json", "0 10 * * 1-5"))
  assert_true(periodic_test_has_entry(entries, "weekly.json", "0 9 * * 1"))

  registry.apply_sync({
    changed_plans: [],
    added_one_shots: [],
    removed_one_shots: [],
    added_periodics: [],
    removed_periodics: [
      {
        filename: "daily.json",
        event: {
          channel_id: "slack-acme/C123",
          text: "daily",
          schedule: "0 10 * * 1-5",
          timezone: "Asia/Singapore",
        },
      },
    ],
  })
  assert_eq(registry.list_entries().length(), 1)
  assert_eq(registry.list_entries()[0].filename, "weekly.json")
}

fn periodic_test_has_entry(
  entries : Array[MomRegisteredPeriodic],
  filename : String,
  schedule : String
) -> Bool {
  for entry in entries {
    if entry.filename == filename && entry.event.schedule == schedule {
      return true
    }
  }
  false
}
