pub fn MomHostDriver::new(
  host : MomInMemoryHost,
  callbacks : MomHostCallbacks
) -> MomHostDriver {
  { host: Ref::new(host), callbacks }
}

pub fn MomHostDriver::step(
  self : MomHostDriver,
  input : MomHostInput
) -> Result[MomHostStep, MomHostStepError] {
  self.host.val.step_with_callbacks(input, self.callbacks)
}

pub fn MomHostDriver::sync(
  self : MomHostDriver,
  now : String
) -> Result[MomHostStep, MomHostStepError] {
  self.step(Sync(now))
}

pub fn MomHostDriver::handle_message(
  self : MomHostDriver,
  message : ChannelMessage
) -> Result[MomHostStep, MomHostStepError] {
  self.step(Message(message))
}

pub fn MomHostDriver::file_changed(
  self : MomHostDriver,
  filename : String,
  now_ms : UInt64
) -> Result[MomHostStep, MomHostStepError] {
  self.step(FileChanged(filename, now_ms))
}

pub fn MomHostDriver::wakeup(
  self : MomHostDriver,
  now : String
) -> Result[MomHostStep, MomHostStepError] {
  self.step(Wakeup(now))
}

pub fn MomHostDriver::dispatch_periodic(
  self : MomHostDriver,
  filename : String,
  now : String
) -> Result[MomHostStep, MomHostStepError] {
  self.step(Periodic(filename, now))
}

pub fn MomHostDriver::events_dir(self : MomHostDriver) -> String {
  self.host.val.events_dir()
}

pub fn MomHostDriver::next_due_at_ms(self : MomHostDriver) -> UInt64? {
  self.host.val.next_due_at_ms()
}

pub fn MomHostDriver::list_pending_file_changes(
  self : MomHostDriver
) -> Array[MomPendingEventFile] {
  self.host.val.list_pending_file_changes()
}

pub fn MomHostDriver::handle_state(self : MomHostDriver) -> MomEventHandleState {
  self.host.val.handle_state()
}

pub fn MomHostDriver::list_event_files(
  self : MomHostDriver
) -> Array[MomEventFile] {
  self.host.val.list_event_files()
}

pub fn MomHostDriver::list_sent_messages(
  self : MomHostDriver
) -> Array[AdapterSentMessage] {
  self.host.val.list_sent_messages()
}
