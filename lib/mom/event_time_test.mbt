test "parse_mom_timestamp_ms normalizes timezone offsets and fractions" {
  let utc = parse_mom_timestamp_ms("2026-04-17T02:00:00Z").unwrap()
  let offset = parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap()
  let fractional = parse_mom_timestamp_ms("2026-04-17T10:00:00.250+08:00").unwrap()

  assert_eq(utc, offset)
  assert_eq(fractional, offset + 250UL)
}

test "parse_mom_timestamp_ms rejects malformed timestamps" {
  let missing_timezone = parse_mom_timestamp_ms("2026-04-17T10:00:00")
  let invalid_month = parse_mom_timestamp_ms("2026-13-17T10:00:00Z")

  assert_true(missing_timezone is Err(_))
  assert_true(invalid_month is Err(_))
}
