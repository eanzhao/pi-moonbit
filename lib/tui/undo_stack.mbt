///| 撤销/重做栈（用于编辑器等组件）。

pub(all) struct UndoStack[T] {
  mut history : Array[T]
  mut cursor : Int  // 当前位置；cursor == history.length - 1 表示最新状态
  max_size : Int
}

pub fn[T] UndoStack::new(max_size? : Int = 100) -> UndoStack[T] {
  { history: [], cursor: -1, max_size }
}

///| 推入新状态（这会丢弃 cursor 之后的历史）。
pub fn[T] UndoStack::push(self : UndoStack[T], state : T) -> Unit {
  // Drop redo history
  while self.history.length() > self.cursor + 1 {
    ignore(self.history.pop())
  }
  self.history.push(state)
  self.cursor = self.history.length() - 1
  // Enforce max size
  while self.history.length() > self.max_size {
    let shifted : Array[T] = []
    for i = 1; i < self.history.length(); i = i + 1 {
      shifted.push(self.history[i])
    }
    self.history.clear()
    for item in shifted {
      self.history.push(item)
    }
    self.cursor = self.history.length() - 1
  }
}

///| 撤销（返回上一个状态）。
pub fn[T] UndoStack::undo(self : UndoStack[T]) -> T? {
  if self.cursor <= 0 { return None }
  self.cursor = self.cursor - 1
  Some(self.history[self.cursor])
}

///| 重做（返回下一个状态）。
pub fn[T] UndoStack::redo(self : UndoStack[T]) -> T? {
  if self.cursor >= self.history.length() - 1 { return None }
  self.cursor = self.cursor + 1
  Some(self.history[self.cursor])
}

///| 当前状态。
pub fn[T] UndoStack::current(self : UndoStack[T]) -> T? {
  if self.cursor >= 0 && self.cursor < self.history.length() {
    Some(self.history[self.cursor])
  } else {
    None
  }
}

pub fn[T] UndoStack::can_undo(self : UndoStack[T]) -> Bool {
  self.cursor > 0
}

pub fn[T] UndoStack::can_redo(self : UndoStack[T]) -> Bool {
  self.cursor < self.history.length() - 1
}

pub fn[T] UndoStack::clear(self : UndoStack[T]) -> Unit {
  self.history.clear()
  self.cursor = -1
}
