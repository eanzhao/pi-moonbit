pub fn MomRunner::new(
  workspace_dir : String,
  started_at : String,
  debounce_ms? : UInt64 = 100UL
) -> MomRunner {
  {
    event_loop: MomEventLoop::new(workspace_dir, started_at, debounce_ms~),
    handle_state: MomEventHandleState::new(),
  }
}

pub fn MomRunner::events_dir(self : MomRunner) -> String {
  self.event_loop.events_dir()
}

pub fn MomRunner::note_file_change(
  self : MomRunner,
  filename : String,
  now_ms : UInt64
) -> Unit {
  self.event_loop.note_file_change(filename, now_ms)
}

pub fn MomRunner::clear_file_change(
  self : MomRunner,
  filename : String
) -> Bool {
  self.event_loop.clear_file_change(filename)
}

pub fn MomRunner::next_due_at_ms(self : MomRunner) -> UInt64? {
  self.event_loop.next_due_at_ms()
}

pub fn MomRunner::list_pending_file_changes(
  self : MomRunner
) -> Array[MomPendingEventFile] {
  self.event_loop.list_pending_file_changes()
}

pub fn MomRunner::list_periodic_entries(
  self : MomRunner
) -> Array[MomRegisteredPeriodic] {
  self.event_loop.list_periodic_entries()
}

pub fn[T : MomEventHandleRuntime] MomRunner::sync_handles(
  self : MomRunner,
  event_runtime : MomEventWorkspaceRuntime,
  handle_runtime : T,
  now : String
) -> Result[MomRunnerSyncResult, MomRunnerError] {
  let sync = match self.event_loop.sync_workspace(event_runtime, now) {
    Ok(value) => value
    Err(message) => return Err(EventRuntimeFailed(message))
  }
  let handle_plan = self.event_loop.plan_handles(self.handle_state)
  let next_state = match apply_event_handle_plan(handle_runtime, handle_plan) {
    Ok(value) => value
    Err(message) => return Err(HandleRuntimeFailed(message))
  }
  self.handle_state = next_state
  Ok({ sync, handle_plan })
}

pub fn[T : PlatformAdapter, H : MomEventHandleRuntime] MomRunner::handle_message(
  self : MomRunner,
  event_runtime : MomEventWorkspaceRuntime,
  handle_runtime : H,
  adapter : T,
  mom : MomAgent,
  message : ChannelMessage,
  now? : String = message.timestamp,
  channel_memory? : String? = None,
  skills? : Array[MomSkill] = [],
) -> Result[MomRunnerTurnResult, MomRunnerError] {
  let run = match run_mom_turn_with_adapter(
    adapter,
    mom,
    message,
    channel_memory~,
    skills~,
  ) {
    Ok(value) => value
    Err(error) => return Err(AgentFailed(error))
  }
  let sync = match self.sync_handles(event_runtime, handle_runtime, now) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ run, handle_plan: sync.handle_plan })
}

pub fn[T : PlatformAdapter, H : MomEventHandleRuntime] MomRunner::tick(
  self : MomRunner,
  event_runtime : MomEventWorkspaceRuntime,
  handle_runtime : H,
  adapter : T,
  mom : MomAgent,
  now : String
) -> Result[MomRunnerTickResult, MomRunnerError] {
  let tick = match self.event_loop.tick(event_runtime, adapter, mom, now) {
    Ok(value) => value
    Err(error) => return Err(EventDispatchFailed(error))
  }
  let sync = match self.sync_handles(event_runtime, handle_runtime, now) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ tick, handle_plan: sync.handle_plan })
}

pub fn[T : PlatformAdapter, H : MomEventHandleRuntime] MomRunner::dispatch_periodic(
  self : MomRunner,
  event_runtime : MomEventWorkspaceRuntime,
  handle_runtime : H,
  adapter : T,
  mom : MomAgent,
  filename : String,
  now : String
) -> Result[MomRunnerPeriodicResult, MomRunnerError] {
  let dispatch = match self.event_loop.dispatch_periodic(filename, adapter, mom, now) {
    Ok(value) => value
    Err(error) => return Err(EventDispatchFailed(error))
  }
  let sync = match self.sync_handles(event_runtime, handle_runtime, now) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ dispatch, handle_plan: sync.handle_plan })
}
