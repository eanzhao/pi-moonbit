test "pending queue drains one item at a time by default" {
  let queue = PendingMessageQueue::new()
  queue.enqueue(@ai.Message::User({ content: [@ai.ContentBlock::Text("first")] }))
  queue.enqueue(@ai.Message::User({ content: [@ai.ContentBlock::Text("second")] }))
  let first = queue.drain()
  assert_eq(first.length(), 1)
  let second = queue.drain()
  assert_eq(second.length(), 1)
  assert_false(queue.has_items())
}

test "pending queue can drain all messages" {
  let queue = PendingMessageQueue::new(mode=All)
  queue.enqueue(@ai.Message::User({ content: [@ai.ContentBlock::Text("first")] }))
  queue.enqueue(@ai.Message::User({ content: [@ai.ContentBlock::Text("second")] }))
  let drained = queue.drain()
  assert_eq(drained.length(), 2)
  assert_false(queue.has_items())
}
