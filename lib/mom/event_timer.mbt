pub fn MomOneShotTimerRegistry::new() -> MomOneShotTimerRegistry {
  { timers: [] }
}

pub fn MomOneShotTimerRegistry::list_timers(
  self : MomOneShotTimerRegistry
) -> Array[MomScheduledTimer] {
  sort_scheduled_timers(self.timers.copy())
}

pub fn MomOneShotTimerRegistry::apply_sync(
  self : MomOneShotTimerRegistry,
  sync : MomEventHostSync
) -> Result[Unit, String] {
  for removed in sync.removed_one_shots {
    ignore(self.remove(removed.filename))
  }
  for added in sync.added_one_shots {
    match self.register(added) {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
  }
  Ok(())
}

pub fn MomOneShotTimerRegistry::register(
  self : MomOneShotTimerRegistry,
  scheduled : MomScheduledOneShot
) -> Result[Unit, String] {
  let due_at_ms = match parse_mom_timestamp_ms(scheduled.event.at) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let timer : MomScheduledTimer = {
    filename: scheduled.filename,
    event: scheduled.event,
    due_at_ms,
  }
  for i in 0..<self.timers.length() {
    if self.timers[i].filename == scheduled.filename {
      self.timers[i] = timer
      return Ok(())
    }
  }
  self.timers.push(timer)
  Ok(())
}

pub fn MomOneShotTimerRegistry::remove(
  self : MomOneShotTimerRegistry,
  filename : String
) -> Bool {
  let retained : Array[MomScheduledTimer] = []
  let mut removed = false
  for item in self.timers {
    if item.filename == filename {
      removed = true
    } else {
      retained.push(item)
    }
  }
  self.timers = retained
  removed
}

pub fn MomOneShotTimerRegistry::next_due_at_ms(
  self : MomOneShotTimerRegistry
) -> UInt64? {
  match self.list_timers() {
    [head, .._rest] => Some(head.due_at_ms)
    [] => None
  }
}

pub fn MomOneShotTimerRegistry::flush_due(
  self : MomOneShotTimerRegistry,
  now_ms : UInt64
) -> Array[MomScheduledTimer] {
  let due : Array[MomScheduledTimer] = []
  let retained : Array[MomScheduledTimer] = []
  for item in self.timers {
    if item.due_at_ms <= now_ms {
      due.push(item)
    } else {
      retained.push(item)
    }
  }
  self.timers = retained
  sort_scheduled_timers(due)
}

fn sort_scheduled_timers(
  items : Array[MomScheduledTimer]
) -> Array[MomScheduledTimer] {
  let mut remaining = items.copy()
  let sorted : Array[MomScheduledTimer] = []
  while remaining.length() > 0 {
    let earliest_index = earliest_scheduled_timer_index(remaining)
    sorted.push(remaining[earliest_index])
    remaining = filter_scheduled_timers_by_index(remaining, earliest_index)
  }
  sorted
}

fn earliest_scheduled_timer_index(items : Array[MomScheduledTimer]) -> Int {
  let mut earliest_index = 0
  for i in 1..<items.length() {
    if scheduled_timer_sort_key(items[i]) < scheduled_timer_sort_key(items[earliest_index]) {
      earliest_index = i
    }
  }
  earliest_index
}

fn scheduled_timer_sort_key(item : MomScheduledTimer) -> String {
  item.due_at_ms.to_string() + "\n" + item.filename
}

fn filter_scheduled_timers_by_index(
  items : Array[MomScheduledTimer],
  index : Int
) -> Array[MomScheduledTimer] {
  let filtered : Array[MomScheduledTimer] = []
  for i in 0..<items.length() {
    if i != index {
      filtered.push(items[i])
    }
  }
  filtered
}
