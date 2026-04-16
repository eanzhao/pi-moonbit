test "event planner deletes stale immediate events and triggers fresh ones" {
  let stale = plan_mom_event(
    {
      filename: "stale.json",
      content: "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"stale\"}",
      modified_at: Some("2026-04-16T11:59:59Z"),
    },
    "2026-04-16T12:00:00Z",
    "2026-04-16T12:05:00Z",
  ).unwrap()
  match stale {
    Delete(filename) => assert_eq(filename, "stale.json")
    _ => fail("expected delete")
  }

  let fresh = plan_mom_event(
    {
      filename: "fresh.json",
      content: "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"fresh\"}",
      modified_at: Some("2026-04-16T12:00:01Z"),
    },
    "2026-04-16T12:00:00Z",
    "2026-04-16T12:05:00Z",
  ).unwrap()
  match fresh {
    Trigger(trigger) => {
      assert_eq(trigger.filename, "fresh.json")
      assert_true(trigger.delete_after)
      assert_eq(trigger.message, "[EVENT:fresh.json:immediate] fresh")
    }
    _ => fail("expected trigger")
  }
}

test "event planner schedules future one-shot and triggers due one-shot with timezone offsets" {
  let future = plan_mom_event(
    {
      filename: "future.json",
      content: "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      modified_at: None,
    },
    "2026-04-16T12:00:00Z",
    "2026-04-17T09:00:00+08:00",
  ).unwrap()
  match future {
    ScheduleOneShot(value) => {
      assert_eq(value.filename, "future.json")
      assert_eq(value.event.at, "2026-04-17T10:00:00+08:00")
    }
    _ => fail("expected scheduled one-shot")
  }

  let due = plan_mom_event(
    {
      filename: "due.json",
      content: "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"due\",\"at\":\"2026-04-17T01:00:00Z\"}",
      modified_at: None,
    },
    "2026-04-16T12:00:00Z",
    "2026-04-17T09:00:00+08:00",
  ).unwrap()
  match due {
    Trigger(trigger) => {
      assert_true(trigger.delete_after)
      assert_eq(trigger.message, "[EVENT:due.json:one-shot:2026-04-17T01:00:00Z] due")
    }
    _ => fail("expected trigger")
  }
}

test "event planner registers periodic events and preserves parse failures" {
  let periodic = plan_mom_event(
    {
      filename: "periodic.json",
      content: "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"check\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      modified_at: None,
    },
    "2026-04-16T12:00:00Z",
    "2026-04-16T12:05:00Z",
  ).unwrap()
  match periodic {
    RegisterPeriodic(value) => {
      assert_eq(value.filename, "periodic.json")
      assert_eq(value.event.schedule, "0 9 * * 1-5")
    }
    _ => fail("expected periodic registration")
  }

  let invalid = plan_mom_event(
    {
      filename: "broken.json",
      content: "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"broken\"}",
      modified_at: None,
    },
    "2026-04-16T12:00:00Z",
    "2026-04-16T12:05:00Z",
  ).unwrap()
  match invalid {
    Invalid(filename, message) => {
      assert_eq(filename, "broken.json")
      assert_true(message.contains("one-shot event is missing at"))
    }
    _ => fail("expected invalid event")
  }
}

test "event planner can plan multiple files in order" {
  let plans = plan_mom_events(
    [
      {
        filename: "a.json",
        content: "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"a\"}",
        modified_at: None,
      },
      {
        filename: "b.json",
        content: "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"b\",\"schedule\":\"0 9 * * *\",\"timezone\":\"UTC\"}",
        modified_at: None,
      },
    ],
    "2026-04-16T12:00:00Z",
    "2026-04-16T12:05:00Z",
  ).unwrap()
  assert_eq(plans.length(), 2)
  match plans[0] {
    Trigger(_) => ()
    _ => fail("expected trigger")
  }
  match plans[1] {
    RegisterPeriodic(_) => ()
    _ => fail("expected periodic registration")
  }
}
