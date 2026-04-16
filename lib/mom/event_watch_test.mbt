test "event debounce queue delays flush until debounce window passes" {
  let queue = MomEventDebounceQueue::new(debounce_ms=100UL)

  queue.note_change("a.json", 1_000UL)
  assert_eq(queue.flush_due(1_099UL).length(), 0)

  let due = queue.flush_due(1_100UL)
  assert_eq(due, ["a.json"])
  assert_eq(queue.list_pending().length(), 0)
}

test "event debounce queue refreshes deadline for repeated changes" {
  let queue = MomEventDebounceQueue::new(debounce_ms=100UL)

  queue.note_change("a.json", 1_000UL)
  queue.note_change("a.json", 1_050UL)

  assert_eq(queue.flush_due(1_149UL).length(), 0)
  assert_eq(queue.flush_due(1_150UL), ["a.json"])
}

test "event debounce queue sorts due files by deadline then filename" {
  let queue = MomEventDebounceQueue::new(debounce_ms=100UL)

  queue.note_change("b.json", 1_000UL)
  queue.note_change("a.json", 1_000UL)
  queue.note_change("c.json", 900UL)

  let due = queue.flush_due(1_100UL)
  assert_eq(due, ["c.json", "a.json", "b.json"])
}

test "event debounce queue can clear pending files" {
  let queue = MomEventDebounceQueue::new(debounce_ms=100UL)

  queue.note_change("a.json", 1_000UL)
  queue.note_change("b.json", 1_000UL)

  assert_true(queue.clear("a.json"))
  assert_false(queue.clear("missing.json"))
  assert_eq(queue.list_pending().length(), 1)
  assert_eq(queue.list_pending()[0].filename, "b.json")
}
