pub fn InMemoryEventWorkspace::new(
  files? : Array[MomEventFile] = []
) -> InMemoryEventWorkspace {
  { files: sort_in_memory_event_files(files.copy()) }
}

pub fn InMemoryEventWorkspace::list_event_files(
  self : InMemoryEventWorkspace
) -> Array[MomEventFile] {
  sort_in_memory_event_files(self.files.copy())
}

pub fn InMemoryEventWorkspace::upsert_file(
  self : InMemoryEventWorkspace,
  filename : String,
  content : String,
  modified_at? : String? = None
) -> Unit {
  let file : MomEventFile = { filename, content, modified_at }
  for i in 0..<self.files.length() {
    if self.files[i].filename == filename {
      self.files[i] = file
      return
    }
  }
  self.files.push(file)
}

pub fn InMemoryEventWorkspace::upsert_event(
  self : InMemoryEventWorkspace,
  filename : String,
  event : MomEvent,
  modified_at? : String? = None
) -> Unit {
  self.upsert_file(filename, mom_event_file_text(event), modified_at~)
}

pub fn InMemoryEventWorkspace::delete_event_file(
  self : InMemoryEventWorkspace,
  filename : String
) -> Bool {
  let retained : Array[MomEventFile] = []
  let mut removed = false
  for item in self.files {
    if item.filename == filename {
      removed = true
    } else {
      retained.push(item)
    }
  }
  self.files = retained
  removed
}

pub fn in_memory_event_workspace_runtime(
  workspace : Ref[InMemoryEventWorkspace],
  workspace_dir : String
) -> MomEventWorkspaceRuntime {
  MomEventWorkspaceRuntime::new(
    fn(path) {
      let filename = match in_memory_event_workspace_filename(workspace_dir, path) {
        Some(value) => value
        None => return Err("path is outside events dir: " + path)
      }
      match in_memory_event_workspace_get(workspace.val, filename) {
        Some(file) => Ok(file.content)
        None => Err("missing file: " + path)
      }
    },
    fn(dir) {
      let events_dir = workspace_events_dir(workspace_dir)
      if dir != events_dir {
        return Err("unsupported dir: " + dir)
      }
      let listed : Array[String] = []
      for file in workspace.val.list_event_files() {
        listed.push(workspace_event_file_path(workspace_dir, file.filename))
      }
      Ok(listed)
    },
    read_modified_at=fn(path) {
      let filename = match in_memory_event_workspace_filename(workspace_dir, path) {
        Some(value) => value
        None => return Err("path is outside events dir: " + path)
      }
      match in_memory_event_workspace_get(workspace.val, filename) {
        Some(file) => Ok(file.modified_at)
        None => Err("missing file: " + path)
      }
    },
    delete_file=fn(path) {
      let filename = match in_memory_event_workspace_filename(workspace_dir, path) {
        Some(value) => value
        None => return Err("path is outside events dir: " + path)
      }
      if workspace.val.delete_event_file(filename) {
        Ok(())
      } else {
        Err("missing file: " + path)
      }
    },
  )
}

pub fn MomInMemoryHost::new(
  config : MomAgentConfig,
  adapter_name : String,
  channels : Array[ChannelInfo],
  users : Array[UserInfo],
  started_at : String,
  debounce_ms? : UInt64 = 100UL,
  event_files? : Array[MomEventFile] = []
) -> MomInMemoryHost {
  let workspace_dir = config.workspace_dir
  {
    workspace_dir,
    runner: MomRunner::new(workspace_dir, started_at, debounce_ms~),
    event_workspace: Ref::new(InMemoryEventWorkspace::new(files=event_files)),
    handle_runtime: InMemoryEventHandleRuntime::new(),
    adapter: InMemoryPlatformAdapter::new(adapter_name, channels, users),
    mom: MomAgent::new(config),
  }
}

pub fn MomInMemoryHost::event_runtime(self : MomInMemoryHost) -> MomEventWorkspaceRuntime {
  in_memory_event_workspace_runtime(self.event_workspace, self.workspace_dir)
}

pub fn MomInMemoryHost::events_dir(self : MomInMemoryHost) -> String {
  self.runner.events_dir()
}

pub fn MomInMemoryHost::note_file_change(
  self : MomInMemoryHost,
  filename : String,
  now_ms : UInt64
) -> Unit {
  self.runner.note_file_change(filename, now_ms)
}

pub fn MomInMemoryHost::next_due_at_ms(self : MomInMemoryHost) -> UInt64? {
  self.runner.next_due_at_ms()
}

pub fn MomInMemoryHost::list_pending_file_changes(
  self : MomInMemoryHost
) -> Array[MomPendingEventFile] {
  self.runner.list_pending_file_changes()
}

pub fn MomInMemoryHost::clear_file_change(
  self : MomInMemoryHost,
  filename : String
) -> Bool {
  self.runner.clear_file_change(filename)
}

pub fn MomInMemoryHost::write_event(
  self : MomInMemoryHost,
  filename : String,
  event : MomEvent,
  modified_at? : String? = None
) -> Unit {
  self.event_workspace.val.upsert_event(filename, event, modified_at~)
}

pub fn MomInMemoryHost::delete_event_file(
  self : MomInMemoryHost,
  filename : String
) -> Bool {
  self.event_workspace.val.delete_event_file(filename)
}

pub fn MomInMemoryHost::list_event_files(
  self : MomInMemoryHost
) -> Array[MomEventFile] {
  self.event_workspace.val.list_event_files()
}

pub fn MomInMemoryHost::handle_state(self : MomInMemoryHost) -> MomEventHandleState {
  self.handle_runtime.snapshot()
}

pub fn MomInMemoryHost::list_handle_operations(
  self : MomInMemoryHost
) -> Array[MomEventHandleOp] {
  self.handle_runtime.list_operations()
}

pub fn MomInMemoryHost::drain_handle_operations(
  self : MomInMemoryHost
) -> Array[MomEventHandleOp] {
  self.handle_runtime.drain_operations()
}

pub fn MomInMemoryHost::list_sent_messages(
  self : MomInMemoryHost
) -> Array[AdapterSentMessage] {
  self.adapter.sent_messages.copy()
}

pub fn MomInMemoryHost::sync(
  self : MomInMemoryHost,
  now : String
) -> Result[MomRunnerSyncResult, MomRunnerError] {
  self.runner.sync_handles(self.event_runtime(), self.handle_runtime, now)
}

pub fn MomInMemoryHost::handle_message(
  self : MomInMemoryHost,
  message : ChannelMessage
) -> Result[MomRunnerTurnResult, MomRunnerError] {
  self.runner.handle_message(
    self.event_runtime(),
    self.handle_runtime,
    self.adapter,
    self.mom,
    message,
  )
}

pub fn MomInMemoryHost::tick(
  self : MomInMemoryHost,
  now : String
) -> Result[MomRunnerTickResult, MomRunnerError] {
  self.runner.tick(
    self.event_runtime(),
    self.handle_runtime,
    self.adapter,
    self.mom,
    now,
  )
}

pub fn MomInMemoryHost::dispatch_periodic(
  self : MomInMemoryHost,
  filename : String,
  now : String
) -> Result[MomRunnerPeriodicResult, MomRunnerError] {
  self.runner.dispatch_periodic(
    self.event_runtime(),
    self.handle_runtime,
    self.adapter,
    self.mom,
    filename,
    now,
  )
}

pub fn MomInMemoryHost::handle_input(
  self : MomInMemoryHost,
  input : MomHostInput
) -> Result[MomHostResult, MomRunnerError] {
  match input {
    Sync(now) =>
      match self.sync(now) {
        Ok(result) => Ok(Synced(result))
        Err(error) => Err(error)
      }
    Message(message) =>
      match self.handle_message(message) {
        Ok(result) => Ok(MessageHandled(result))
        Err(error) => Err(error)
      }
    FileChanged(filename, now_ms) => {
      self.note_file_change(filename, now_ms)
      Ok(FileQueued(self.list_pending_file_changes()))
    }
    Wakeup(now) =>
      match self.tick(now) {
        Ok(result) => Ok(Woke(result))
        Err(error) => Err(error)
      }
    Periodic(filename, now) =>
      match self.dispatch_periodic(filename, now) {
        Ok(result) => Ok(PeriodicDispatched(result))
        Err(error) => Err(error)
      }
  }
}

pub fn mom_host_result_handle_plan(
  result : MomHostResult
) -> MomEventHandlePlan? {
  match result {
    Synced(sync) => Some(sync.handle_plan)
    MessageHandled(turn) => Some(turn.handle_plan)
    Woke(tick) => Some(tick.handle_plan)
    PeriodicDispatched(periodic) => Some(periodic.handle_plan)
    FileQueued(_) => None
  }
}

pub fn MomInMemoryHost::step(
  self : MomInMemoryHost,
  input : MomHostInput
) -> Result[MomHostStep, MomRunnerError] {
  let result = match self.handle_input(input) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let handle_plan = mom_host_result_handle_plan(result)
  let handle_operations = self.drain_handle_operations()
  Ok({ result, handle_plan, handle_operations })
}

pub fn[T : MomEventHandleRuntime] MomInMemoryHost::step_with_handle_runtime(
  self : MomInMemoryHost,
  input : MomHostInput,
  runtime : T
) -> Result[MomHostStep, MomHostStepError] {
  let step = match self.step(input) {
    Ok(value) => value
    Err(error) => return Err(RunnerFailed(error))
  }
  match apply_mom_host_step_handle_operations(runtime, step) {
    Ok(_) => Ok(step)
    Err(message) => Err(HandleApplyFailed(message))
  }
}

pub fn run_mom_host_input_with_callbacks(
  host : MomInMemoryHost,
  input : MomHostInput,
  set_watch_dir_fn : (String?) -> Result[Unit, String],
  set_wakeup_due_at_ms_fn : (UInt64?) -> Result[Unit, String],
  register_periodic_fn : (MomRegisteredPeriodic) -> Result[Unit, String],
  remove_periodic_fn : (String) -> Result[Unit, String]
) -> Result[MomHostStep, MomHostStepError] {
  let runtime = CallbackEventHandleRuntime::new(
    set_watch_dir_fn,
    set_wakeup_due_at_ms_fn,
    register_periodic_fn,
    remove_periodic_fn,
  )
  host.step_with_handle_runtime(input, runtime)
}

fn in_memory_event_workspace_get(
  workspace : InMemoryEventWorkspace,
  filename : String
) -> MomEventFile? {
  for file in workspace.files {
    if file.filename == filename {
      return Some(file)
    }
  }
  None
}

fn in_memory_event_workspace_filename(
  workspace_dir : String,
  path : String
) -> String? {
  if !path.contains("/") {
    return Some(path)
  }
  let events_dir = workspace_events_dir(workspace_dir)
  let prefix = if events_dir.has_suffix("/") { events_dir } else { events_dir + "/" }
  if path.has_prefix(prefix) {
    Some(path[prefix.length():].to_string())
  } else {
    None
  }
}

fn sort_in_memory_event_files(
  files : Array[MomEventFile]
) -> Array[MomEventFile] {
  let mut remaining = files.copy()
  let sorted : Array[MomEventFile] = []
  while remaining.length() > 0 {
    let earliest_index = earliest_in_memory_event_file_index(remaining)
    sorted.push(remaining[earliest_index])
    remaining = filter_in_memory_event_files_by_index(remaining, earliest_index)
  }
  sorted
}

fn earliest_in_memory_event_file_index(
  files : Array[MomEventFile]
) -> Int {
  let mut earliest_index = 0
  for i in 1..<files.length() {
    if files[i].filename < files[earliest_index].filename {
      earliest_index = i
    }
  }
  earliest_index
}

fn filter_in_memory_event_files_by_index(
  files : Array[MomEventFile],
  index : Int
) -> Array[MomEventFile] {
  let filtered : Array[MomEventFile] = []
  for i in 0..<files.length() {
    if i != index {
      filtered.push(files[i])
    }
  }
  filtered
}
