pub fn MomHostRuntime::new(
  step_fn : (MomHostInput) -> Result[MomHostStep, MomHostStepError],
  events_dir_fn : () -> String,
  next_due_at_ms_fn : () -> UInt64?,
  list_pending_file_changes_fn : () -> Array[MomPendingEventFile],
  handle_state_fn : () -> MomEventHandleState,
  write_event_fn : (String, MomEvent, String?) -> Unit,
  delete_event_file_fn : (String) -> Bool,
  clear_file_change_fn : (String) -> Bool,
  list_event_files_fn : () -> Array[MomEventFile],
  list_sent_messages_fn : () -> Array[AdapterSentMessage]
) -> MomHostRuntime {
  {
    step_fn,
    events_dir_fn,
    next_due_at_ms_fn,
    list_pending_file_changes_fn,
    handle_state_fn,
    write_event_fn,
    delete_event_file_fn,
    clear_file_change_fn,
    list_event_files_fn,
    list_sent_messages_fn,
  }
}

pub fn MomHostRuntime::step(
  self : MomHostRuntime,
  input : MomHostInput
) -> Result[MomHostStep, MomHostStepError] {
  (self.step_fn)(input)
}

pub fn MomHostRuntime::sync(
  self : MomHostRuntime,
  now : String
) -> Result[MomHostStep, MomHostStepError] {
  self.step(Sync(now))
}

pub fn MomHostRuntime::handle_message(
  self : MomHostRuntime,
  message : ChannelMessage
) -> Result[MomHostStep, MomHostStepError] {
  self.step(Message(message))
}

pub fn MomHostRuntime::file_changed(
  self : MomHostRuntime,
  filename : String,
  now_ms : UInt64
) -> Result[MomHostStep, MomHostStepError] {
  self.step(FileChanged(filename, now_ms))
}

pub fn MomHostRuntime::event_filename(
  self : MomHostRuntime,
  path : String
) -> String? {
  event_filename_in_dir(self.events_dir(), path)
}

pub fn MomHostRuntime::file_changed_path(
  self : MomHostRuntime,
  path : String,
  now_ms : UInt64
) -> Result[MomHostStep?, MomHostStepError] {
  match self.event_filename(path) {
    Some(filename) =>
      match self.file_changed(filename, now_ms) {
        Ok(step) => Ok(Some(step))
        Err(error) => Err(error)
      }
    None => Ok(None)
  }
}

pub fn MomHostRuntime::wakeup(
  self : MomHostRuntime,
  now : String
) -> Result[MomHostStep, MomHostStepError] {
  self.step(Wakeup(now))
}

pub fn MomHostRuntime::dispatch_periodic(
  self : MomHostRuntime,
  filename : String,
  now : String
) -> Result[MomHostStep, MomHostStepError] {
  self.step(Periodic(filename, now))
}

pub fn MomHostRuntime::events_dir(self : MomHostRuntime) -> String {
  (self.events_dir_fn)()
}

pub fn MomHostRuntime::next_due_at_ms(self : MomHostRuntime) -> UInt64? {
  (self.next_due_at_ms_fn)()
}

pub fn MomHostRuntime::list_pending_file_changes(
  self : MomHostRuntime
) -> Array[MomPendingEventFile] {
  (self.list_pending_file_changes_fn)()
}

pub fn MomHostRuntime::handle_state(self : MomHostRuntime) -> MomEventHandleState {
  (self.handle_state_fn)()
}

pub fn MomHostRuntime::write_event(
  self : MomHostRuntime,
  filename : String,
  event : MomEvent,
  modified_at? : String? = None
) -> Unit {
  (self.write_event_fn)(filename, event, modified_at)
}

pub fn MomHostRuntime::delete_event_file(
  self : MomHostRuntime,
  filename : String
) -> Bool {
  (self.delete_event_file_fn)(filename)
}

pub fn MomHostRuntime::clear_file_change(
  self : MomHostRuntime,
  filename : String
) -> Bool {
  (self.clear_file_change_fn)(filename)
}

pub fn MomHostRuntime::list_event_files(
  self : MomHostRuntime
) -> Array[MomEventFile] {
  (self.list_event_files_fn)()
}

pub fn MomHostRuntime::list_sent_messages(
  self : MomHostRuntime
) -> Array[AdapterSentMessage] {
  (self.list_sent_messages_fn)()
}

pub fn mom_host_runtime_from_driver(driver : MomHostDriver) -> MomHostRuntime {
  MomHostRuntime::new(
    fn(input) { driver.step(input) },
    fn() { driver.events_dir() },
    fn() { driver.next_due_at_ms() },
    fn() { driver.list_pending_file_changes() },
    fn() { driver.handle_state() },
    fn(filename, event, modified_at) {
      match modified_at {
        Some(value) => driver.write_event(filename, event, modified_at=Some(value))
        None => driver.write_event(filename, event)
      }
    },
    fn(filename) { driver.delete_event_file(filename) },
    fn(filename) { driver.clear_file_change(filename) },
    fn() { driver.list_event_files() },
    fn() { driver.list_sent_messages() },
  )
}

pub fn mom_host_runtime_in_memory(
  config : MomAgentConfig,
  adapter_name : String,
  channels : Array[ChannelInfo],
  users : Array[UserInfo],
  started_at : String,
  callbacks : MomHostCallbacks,
  debounce_ms? : UInt64 = 100UL,
  event_files? : Array[MomEventFile] = []
) -> MomHostRuntime {
  mom_host_runtime_from_driver(MomHostDriver::new_in_memory(
    config,
    adapter_name,
    channels,
    users,
    started_at,
    callbacks,
    debounce_ms~,
    event_files~,
  ))
}

pub fn[T : MomEventHandleRuntime] mom_host_runtime_in_memory_with_handle_runtime(
  config : MomAgentConfig,
  adapter_name : String,
  channels : Array[ChannelInfo],
  users : Array[UserInfo],
  started_at : String,
  runtime : T,
  debounce_ms? : UInt64 = 100UL,
  event_files? : Array[MomEventFile] = []
) -> MomHostRuntime {
  mom_host_runtime_from_driver(MomHostDriver::new_in_memory_with_handle_runtime(
    config,
    adapter_name,
    channels,
    users,
    started_at,
    runtime,
    debounce_ms~,
    event_files~,
  ))
}
