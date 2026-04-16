test "format helpers render cost usage and relative dates" {
  let usage : @ai.Usage = {
    input: 1200,
    output: 40,
    cache_read: 0,
    cache_write: 0,
    total_tokens: 1240,
    cost: {
      input: 0.2,
      output: 0.05,
      cache_read: 0.0,
      cache_write: 0.0,
      total: 0.25,
    },
  }

  assert_eq(format_cost(0.25), "$0.2500")
  assert_eq(format_model_cost(web_ui_test_model().cost), "Free")
  assert_eq(format_usage(usage), "↑1.2k ↓40 $0.2500")
  assert_eq(format_relative_date("2026-04-16T10:00:00.000Z", "2026-04-16T12:00:00.000Z"), "Today")
  assert_eq(format_relative_date("2026-04-15T10:00:00.000Z", "2026-04-16T12:00:00.000Z"), "Yesterday")
  assert_eq(format_relative_date("2026-04-10T10:00:00.000Z", "2026-04-16T12:00:00.000Z"), "6 days ago")
}
