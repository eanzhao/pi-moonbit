test "event json parses and renders trigger messages" {
  let event = parse_mom_event_json(
    "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"Check inbox\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
  ).unwrap()

  assert_eq(mom_event_type_name(event), "periodic")
  assert_eq(mom_event_channel_id(event), "slack-acme/C123")
  assert_eq(mom_event_schedule_text(event), Some("0 9 * * 1-5"))
  assert_eq(
    build_event_trigger_message("daily-inbox.json", event),
    "[EVENT:daily-inbox.json:periodic:0 9 * * 1-5] Check inbox",
  )
}

test "event parser rejects missing required fields" {
  let missing_schedule = parse_mom_event_json(
    "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"Check inbox\",\"timezone\":\"Asia/Singapore\"}",
  )
  assert_true(missing_schedule is Err(_))

  let serialized = mom_event_file_text(MomEvent::OneShot({
    channel_id: "slack-acme/C123",
    text: "Follow up tomorrow",
    at: "2026-04-17T09:00:00+08:00",
  }))
  assert_true(serialized.contains("\"type\": \"one-shot\"") || serialized.contains("\"type\":\"one-shot\""))
  assert_true(serialized.contains("\"channelId\""))
}
