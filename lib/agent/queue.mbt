///| 简单消息队列，支持一次取一个或全部取出。
pub(all) struct PendingMessageQueue {
  mut mode : QueueMode
  mut messages : Array[@ai.Message]
}

///| 创建空队列。
pub fn PendingMessageQueue::new(mode? : QueueMode = OneAtATime) -> PendingMessageQueue {
  { mode, messages: [] }
}

///| 入队一条消息。
pub fn PendingMessageQueue::enqueue(self : PendingMessageQueue, message : @ai.Message) -> Unit {
  self.messages.push(message)
}

///| 是否仍有未处理消息。
pub fn PendingMessageQueue::has_items(self : PendingMessageQueue) -> Bool {
  self.messages.length() > 0
}

///| 清空队列。
pub fn PendingMessageQueue::clear(self : PendingMessageQueue) -> Unit {
  self.messages.clear()
}

///| 按当前模式出队。
pub fn PendingMessageQueue::drain(self : PendingMessageQueue) -> Array[@ai.Message] {
  if self.messages.length() == 0 {
    return []
  }
  match self.mode {
    All => {
      let drained = self.messages.copy()
      self.messages.clear()
      drained
    }
    OneAtATime => {
      let first = self.messages[0]
      let remaining : Array[@ai.Message] = []
      for i = 1; i < self.messages.length(); i = i + 1 {
        remaining.push(self.messages[i])
      }
      self.messages = remaining
      [first]
    }
  }
}
