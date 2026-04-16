pub fn MomEventLoop::new(
  workspace_dir : String,
  started_at : String,
  debounce_ms? : UInt64 = 100UL
) -> MomEventLoop {
  {
    host: MomEventHost::new(workspace_dir, started_at),
    debounce_queue: MomEventDebounceQueue::new(debounce_ms~),
    one_shot_registry: MomOneShotTimerRegistry::new(),
    periodic_registry: MomPeriodicRegistry::new(),
  }
}

pub fn MomEventLoop::list_pending_file_changes(
  self : MomEventLoop
) -> Array[MomPendingEventFile] {
  self.debounce_queue.list_pending()
}

pub fn MomEventLoop::list_one_shot_timers(
  self : MomEventLoop
) -> Array[MomScheduledTimer] {
  self.one_shot_registry.list_timers()
}

pub fn MomEventLoop::list_periodic_entries(
  self : MomEventLoop
) -> Array[MomRegisteredPeriodic] {
  self.periodic_registry.list_entries()
}

pub fn MomEventLoop::next_due_at_ms(self : MomEventLoop) -> UInt64? {
  let next_file_due = self.debounce_queue.next_due_at_ms()
  let next_timer_due = self.one_shot_registry.next_due_at_ms()
  match next_file_due {
    Some(file_due) =>
      match next_timer_due {
        Some(timer_due) => Some(if file_due <= timer_due { file_due } else { timer_due })
        None => Some(file_due)
      }
    None => next_timer_due
  }
}

pub fn MomEventLoop::note_file_change(
  self : MomEventLoop,
  filename : String,
  now_ms : UInt64
) -> Unit {
  self.debounce_queue.note_change(filename, now_ms)
}

pub fn MomEventLoop::clear_file_change(
  self : MomEventLoop,
  filename : String
) -> Bool {
  self.debounce_queue.clear(filename)
}

pub fn MomEventLoop::flush_due_file_changes(
  self : MomEventLoop,
  now_ms : UInt64
) -> Array[String] {
  self.debounce_queue.flush_due(now_ms)
}

pub fn MomEventLoop::sync_workspace(
  self : MomEventLoop,
  runtime : MomEventWorkspaceRuntime,
  now : String
) -> Result[MomEventHostSync, String] {
  let sync = match self.host.poll_sync(runtime, now) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  match self.one_shot_registry.apply_sync(sync) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  self.periodic_registry.apply_sync(sync)
  Ok(sync)
}

pub fn[T : PlatformAdapter] MomEventLoop::process_workspace(
  self : MomEventLoop,
  runtime : MomEventWorkspaceRuntime,
  adapter : T,
  mom : MomAgent,
  now : String
) -> Result[Array[MomEventDispatchResult], MomEventDispatchError] {
  let sync = match self.sync_workspace(runtime, now) {
    Ok(value) => value
    Err(message) => return Err(RuntimeFailed(message))
  }
  dispatch_event_plans_and_cleanup(
    self.host.workspace_dir,
    runtime,
    adapter,
    mom,
    sync.changed_plans,
    now,
  )
}

pub fn[T : PlatformAdapter] MomEventLoop::flush_due_one_shots(
  self : MomEventLoop,
  runtime : MomEventWorkspaceRuntime,
  adapter : T,
  mom : MomAgent,
  now : String
) -> Result[Array[MomEventDispatchResult], MomEventDispatchError] {
  let now_ms = match parse_mom_timestamp_ms(now) {
    Ok(value) => value
    Err(message) => return Err(RuntimeFailed(message))
  }
  let due_timers = self.one_shot_registry.flush_due(now_ms)
  let plans : Array[MomEventPlan] = []
  for timer in due_timers {
    let event = MomEvent::OneShot(timer.event)
    plans.push(Trigger({
      filename: timer.filename,
      event,
      message: build_event_trigger_message(timer.filename, event),
      delete_after: true,
    }))
  }
  dispatch_event_plans_and_cleanup(
    self.host.workspace_dir,
    runtime,
    adapter,
    mom,
    plans,
    now,
  )
}

pub fn[T : PlatformAdapter] MomEventLoop::tick(
  self : MomEventLoop,
  runtime : MomEventWorkspaceRuntime,
  adapter : T,
  mom : MomAgent,
  now : String
) -> Result[MomEventTickResult, MomEventDispatchError] {
  let now_ms = match parse_mom_timestamp_ms(now) {
    Ok(value) => value
    Err(message) => return Err(RuntimeFailed(message))
  }
  let flushed_files = self.flush_due_file_changes(now_ms)
  let workspace_results =
    if flushed_files.length() == 0 {
      []
    } else {
      match self.process_workspace(runtime, adapter, mom, now) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
    }
  let one_shot_results = match self.flush_due_one_shots(runtime, adapter, mom, now) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ flushed_files, workspace_results, one_shot_results })
}

fn[T : PlatformAdapter] dispatch_event_plans_and_cleanup(
  workspace_dir : String,
  runtime : MomEventWorkspaceRuntime,
  adapter : T,
  mom : MomAgent,
  plans : Array[MomEventPlan],
  now : String
) -> Result[Array[MomEventDispatchResult], MomEventDispatchError] {
  let results : Array[MomEventDispatchResult] = []
  let cleanup_filenames : Array[String] = []
  for plan in plans {
    match dispatch_mom_event_plan_with_adapter(adapter, mom, plan, now) {
      Ok(result) => {
        results.push(result)
        match event_loop_cleanup_filename(plan) {
          Some(filename) => cleanup_filenames.push(filename)
          None => ()
        }
      }
      Err(error) => return Err(error)
    }
  }
  for filename in cleanup_filenames {
    let path = workspace_event_file_path(workspace_dir, filename)
    match (runtime.delete_file)(path) {
      Ok(_) => ()
      Err(message) => return Err(RuntimeFailed(message))
    }
  }
  Ok(results)
}

fn event_loop_cleanup_filename(plan : MomEventPlan) -> String? {
  match plan {
    Trigger(value) if value.delete_after => Some(value.filename)
    Delete(filename) => Some(filename)
    Invalid(filename, _message) => Some(filename)
    _ => None
  }
}
