pub fn MomEventHandleState::new(
  watched_dir? : String? = None,
  wakeup_due_at_ms? : UInt64? = None,
  registered_periodics? : Array[MomRegisteredPeriodic] = []
) -> MomEventHandleState {
  {
    watched_dir,
    wakeup_due_at_ms,
    registered_periodics: sort_handle_periodics(registered_periodics.copy()),
  }
}

pub fn MomEventLoop::events_dir(self : MomEventLoop) -> String {
  workspace_events_dir(self.host.workspace_dir)
}

pub fn MomEventLoop::desired_handle_state(
  self : MomEventLoop
) -> MomEventHandleState {
  MomEventHandleState::new(
    watched_dir=Some(self.events_dir()),
    wakeup_due_at_ms=self.next_due_at_ms(),
    registered_periodics=self.list_periodic_entries(),
  )
}

pub fn MomEventLoop::plan_handles(
  self : MomEventLoop,
  current : MomEventHandleState
) -> MomEventHandlePlan {
  let desired = self.desired_handle_state()
  {
    state: desired,
    watch_changed: current.watched_dir != desired.watched_dir,
    wakeup_changed: current.wakeup_due_at_ms != desired.wakeup_due_at_ms,
    added_periodics: diff_handle_added_periodics(
      current.registered_periodics,
      desired.registered_periodics,
    ),
    removed_periodics: diff_handle_removed_periodics(
      current.registered_periodics,
      desired.registered_periodics,
    ),
  }
}

pub fn MomEventHandlePlan::has_changes(self : MomEventHandlePlan) -> Bool {
  self.watch_changed ||
  self.wakeup_changed ||
  self.added_periodics.length() > 0 ||
  self.removed_periodics.length() > 0
}

fn diff_handle_added_periodics(
  previous : Array[MomRegisteredPeriodic],
  current : Array[MomRegisteredPeriodic]
) -> Array[MomRegisteredPeriodic] {
  let added : Array[MomRegisteredPeriodic] = []
  for item in current {
    if !handle_periodics_contains(previous, item) {
      added.push(item)
    }
  }
  added
}

fn diff_handle_removed_periodics(
  previous : Array[MomRegisteredPeriodic],
  current : Array[MomRegisteredPeriodic]
) -> Array[MomRegisteredPeriodic] {
  let removed : Array[MomRegisteredPeriodic] = []
  for item in previous {
    if !handle_periodics_contains(current, item) {
      removed.push(item)
    }
  }
  removed
}

fn handle_periodics_contains(
  items : Array[MomRegisteredPeriodic],
  target : MomRegisteredPeriodic
) -> Bool {
  for item in items {
    if item == target {
      return true
    }
  }
  false
}

fn sort_handle_periodics(
  items : Array[MomRegisteredPeriodic]
) -> Array[MomRegisteredPeriodic] {
  let mut remaining = items.copy()
  let sorted : Array[MomRegisteredPeriodic] = []
  while remaining.length() > 0 {
    let earliest_index = earliest_handle_periodic_index(remaining)
    sorted.push(remaining[earliest_index])
    remaining = filter_handle_periodics_by_index(remaining, earliest_index)
  }
  sorted
}

fn earliest_handle_periodic_index(items : Array[MomRegisteredPeriodic]) -> Int {
  let mut earliest_index = 0
  for i in 1..<items.length() {
    if handle_periodic_sort_key(items[i]) < handle_periodic_sort_key(items[earliest_index]) {
      earliest_index = i
    }
  }
  earliest_index
}

fn handle_periodic_sort_key(item : MomRegisteredPeriodic) -> String {
  item.filename + "\n" + item.event.schedule
}

fn filter_handle_periodics_by_index(
  items : Array[MomRegisteredPeriodic],
  index : Int
) -> Array[MomRegisteredPeriodic] {
  let filtered : Array[MomRegisteredPeriodic] = []
  for i in 0..<items.length() {
    if i != index {
      filtered.push(items[i])
    }
  }
  filtered
}
