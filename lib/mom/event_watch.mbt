pub fn MomEventDebounceQueue::new(
  debounce_ms? : UInt64 = 100UL
) -> MomEventDebounceQueue {
  { debounce_ms, pending: [] }
}

pub fn MomEventDebounceQueue::list_pending(
  self : MomEventDebounceQueue
) -> Array[MomPendingEventFile] {
  sort_pending_event_files(self.pending.copy())
}

pub fn MomEventDebounceQueue::note_change(
  self : MomEventDebounceQueue,
  filename : String,
  now_ms : UInt64
) -> Unit {
  let next_due_at = now_ms + self.debounce_ms
  for i in 0..<self.pending.length() {
    if self.pending[i].filename == filename {
      self.pending[i] = { filename, due_at_ms: next_due_at }
      return
    }
  }
  self.pending.push({ filename, due_at_ms: next_due_at })
}

pub fn MomEventDebounceQueue::clear(
  self : MomEventDebounceQueue,
  filename : String
) -> Bool {
  let retained : Array[MomPendingEventFile] = []
  let mut removed = false
  for item in self.pending {
    if item.filename == filename {
      removed = true
    } else {
      retained.push(item)
    }
  }
  self.pending = retained
  removed
}

pub fn MomEventDebounceQueue::flush_due(
  self : MomEventDebounceQueue,
  now_ms : UInt64
) -> Array[String] {
  let due : Array[MomPendingEventFile] = []
  let retained : Array[MomPendingEventFile] = []
  for item in self.pending {
    if item.due_at_ms <= now_ms {
      due.push(item)
    } else {
      retained.push(item)
    }
  }
  self.pending = retained
  let filenames : Array[String] = []
  for item in sort_pending_event_files(due) {
    filenames.push(item.filename)
  }
  filenames
}

fn sort_pending_event_files(
  items : Array[MomPendingEventFile]
) -> Array[MomPendingEventFile] {
  let mut remaining = items.copy()
  let sorted : Array[MomPendingEventFile] = []
  while remaining.length() > 0 {
    let earliest_index = earliest_pending_event_index(remaining)
    sorted.push(remaining[earliest_index])
    remaining = filter_pending_event_files_by_index(remaining, earliest_index)
  }
  sorted
}

fn earliest_pending_event_index(items : Array[MomPendingEventFile]) -> Int {
  let mut earliest_index = 0
  for i in 1..<items.length() {
    if pending_event_sort_key(items[i]) < pending_event_sort_key(items[earliest_index]) {
      earliest_index = i
    }
  }
  earliest_index
}

fn pending_event_sort_key(item : MomPendingEventFile) -> String {
  item.due_at_ms.to_string() + "\n" + item.filename
}

fn filter_pending_event_files_by_index(
  items : Array[MomPendingEventFile],
  index : Int
) -> Array[MomPendingEventFile] {
  let filtered : Array[MomPendingEventFile] = []
  for i in 0..<items.length() {
    if i != index {
      filtered.push(items[i])
    }
  }
  filtered
}
