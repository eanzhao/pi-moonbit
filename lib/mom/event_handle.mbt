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

pub fn MomEventHandlePlan::operations(self : MomEventHandlePlan) -> Array[MomEventHandleOp] {
  let ops : Array[MomEventHandleOp] = []
  if self.watch_changed {
    ops.push(SetWatchDir(self.state.watched_dir))
  }
  if self.wakeup_changed {
    ops.push(SetWakeup(self.state.wakeup_due_at_ms))
  }
  for removed in self.removed_periodics {
    ops.push(RemovePeriodic(removed.filename))
  }
  for added in self.added_periodics {
    ops.push(RegisterPeriodic(added))
  }
  ops
}

pub fn[T : MomEventHandleRuntime] apply_event_handle_plan(
  runtime : T,
  plan : MomEventHandlePlan
) -> Result[MomEventHandleState, String] {
  match apply_event_handle_operations(runtime, plan.operations()) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  Ok(plan.state)
}

pub fn[T : MomEventHandleRuntime] apply_event_handle_operations(
  runtime : T,
  operations : Array[MomEventHandleOp]
) -> Result[Unit, String] {
  for operation in operations {
    match operation {
      SetWatchDir(watched_dir) =>
        match runtime.set_watch_dir(watched_dir) {
          Ok(_) => ()
          Err(message) => return Err(message)
        }
      SetWakeup(due_at_ms) =>
        match runtime.set_wakeup_due_at_ms(due_at_ms) {
          Ok(_) => ()
          Err(message) => return Err(message)
        }
      RegisterPeriodic(entry) =>
        match runtime.register_periodic(entry) {
          Ok(_) => ()
          Err(message) => return Err(message)
        }
      RemovePeriodic(filename) =>
        match runtime.remove_periodic(filename) {
          Ok(_) => ()
          Err(message) => return Err(message)
        }
    }
  }
  Ok(())
}

pub fn[T : MomEventHandleRuntime] apply_mom_host_step_handle_operations(
  runtime : T,
  step : MomHostStep
) -> Result[Unit, String] {
  apply_event_handle_operations(runtime, step.handle_operations)
}

pub fn InMemoryEventHandleRuntime::new(
  state? : MomEventHandleState = MomEventHandleState::new()
) -> InMemoryEventHandleRuntime {
  {
    watched_dir: state.watched_dir,
    wakeup_due_at_ms: state.wakeup_due_at_ms,
    registered_periodics: state.registered_periodics.copy(),
    operations: [],
  }
}

pub fn InMemoryEventHandleRuntime::snapshot(
  self : InMemoryEventHandleRuntime
) -> MomEventHandleState {
  MomEventHandleState::new(
    watched_dir=self.watched_dir,
    wakeup_due_at_ms=self.wakeup_due_at_ms,
    registered_periodics=self.registered_periodics,
  )
}

pub fn InMemoryEventHandleRuntime::list_operations(
  self : InMemoryEventHandleRuntime
) -> Array[MomEventHandleOp] {
  self.operations.copy()
}

pub fn InMemoryEventHandleRuntime::drain_operations(
  self : InMemoryEventHandleRuntime
) -> Array[MomEventHandleOp] {
  let drained = self.operations.copy()
  self.operations = []
  drained
}

pub fn CallbackEventHandleRuntime::new(
  set_watch_dir_fn : (String?) -> Result[Unit, String],
  set_wakeup_due_at_ms_fn : (UInt64?) -> Result[Unit, String],
  register_periodic_fn : (MomRegisteredPeriodic) -> Result[Unit, String],
  remove_periodic_fn : (String) -> Result[Unit, String]
) -> CallbackEventHandleRuntime {
  {
    set_watch_dir_fn,
    set_wakeup_due_at_ms_fn,
    register_periodic_fn,
    remove_periodic_fn,
  }
}

pub fn MomHostCallbacks::new(
  set_watch_dir_fn : (String?) -> Result[Unit, String],
  set_wakeup_due_at_ms_fn : (UInt64?) -> Result[Unit, String],
  register_periodic_fn : (MomRegisteredPeriodic) -> Result[Unit, String],
  remove_periodic_fn : (String) -> Result[Unit, String]
) -> MomHostCallbacks {
  {
    set_watch_dir_fn,
    set_wakeup_due_at_ms_fn,
    register_periodic_fn,
    remove_periodic_fn,
  }
}

pub fn[T : MomEventHandleRuntime] mom_host_callbacks_from_handle_runtime(
  runtime : T
) -> MomHostCallbacks {
  MomHostCallbacks::new(
    fn(watched_dir) { runtime.set_watch_dir(watched_dir) },
    fn(due_at_ms) { runtime.set_wakeup_due_at_ms(due_at_ms) },
    fn(entry) { runtime.register_periodic(entry) },
    fn(filename) { runtime.remove_periodic(filename) },
  )
}

pub fn MomHostCallbacks::runtime(
  self : MomHostCallbacks
) -> CallbackEventHandleRuntime {
  CallbackEventHandleRuntime::new(
    self.set_watch_dir_fn,
    self.set_wakeup_due_at_ms_fn,
    self.register_periodic_fn,
    self.remove_periodic_fn,
  )
}

pub impl MomEventHandleRuntime for InMemoryEventHandleRuntime with set_watch_dir(self, watched_dir) {
  self.watched_dir = watched_dir
  self.operations.push(SetWatchDir(watched_dir))
  Ok(())
}

pub impl MomEventHandleRuntime for InMemoryEventHandleRuntime with set_wakeup_due_at_ms(self, due_at_ms) {
  self.wakeup_due_at_ms = due_at_ms
  self.operations.push(SetWakeup(due_at_ms))
  Ok(())
}

pub impl MomEventHandleRuntime for InMemoryEventHandleRuntime with register_periodic(self, entry) {
  self.operations.push(RegisterPeriodic(entry))
  for i in 0..<self.registered_periodics.length() {
    if self.registered_periodics[i].filename == entry.filename {
      self.registered_periodics[i] = entry
      return Ok(())
    }
  }
  self.registered_periodics.push(entry)
  Ok(())
}

pub impl MomEventHandleRuntime for InMemoryEventHandleRuntime with remove_periodic(self, filename) {
  self.operations.push(RemovePeriodic(filename))
  let retained : Array[MomRegisteredPeriodic] = []
  for item in self.registered_periodics {
    if item.filename != filename {
      retained.push(item)
    }
  }
  self.registered_periodics = retained
  Ok(())
}

pub impl MomEventHandleRuntime for CallbackEventHandleRuntime with set_watch_dir(self, watched_dir) {
  (self.set_watch_dir_fn)(watched_dir)
}

pub impl MomEventHandleRuntime for CallbackEventHandleRuntime with set_wakeup_due_at_ms(self, due_at_ms) {
  (self.set_wakeup_due_at_ms_fn)(due_at_ms)
}

pub impl MomEventHandleRuntime for CallbackEventHandleRuntime with register_periodic(self, entry) {
  (self.register_periodic_fn)(entry)
}

pub impl MomEventHandleRuntime for CallbackEventHandleRuntime with remove_periodic(self, filename) {
  (self.remove_periodic_fn)(filename)
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
