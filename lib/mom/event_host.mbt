pub fn MomEventWorkspaceRuntime::new(
  read_text : (String) -> Result[String, String],
  list_files : (String) -> Result[Array[String], String],
  read_modified_at? : (String) -> Result[String?, String] = fn(_path) { Ok(None) },
  delete_file? : (String) -> Result[Unit, String] = fn(_path) { Ok(()) }
) -> MomEventWorkspaceRuntime {
  { read_text, list_files, read_modified_at, delete_file }
}

pub fn MomEventHost::new(
  workspace_dir : String,
  started_at : String
) -> MomEventHost {
  {
    workspace_dir,
    started_at,
    observed_plans: [],
    scheduled_one_shots: [],
    registered_periodics: [],
  }
}

pub fn MomEventHost::list_scheduled_one_shots(
  self : MomEventHost
) -> Array[MomScheduledOneShot] {
  self.scheduled_one_shots.copy()
}

pub fn MomEventHost::list_registered_periodics(
  self : MomEventHost
) -> Array[MomRegisteredPeriodic] {
  self.registered_periodics.copy()
}

pub fn MomEventHost::poll(
  self : MomEventHost,
  runtime : MomEventWorkspaceRuntime,
  now : String
) -> Result[Array[MomEventPlan], String] {
  let plans = match plan_workspace_mom_events(
    runtime,
    self.workspace_dir,
    self.started_at,
    now,
  ) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  Ok(self.update_plans(plans))
}

pub fn[T : PlatformAdapter] MomEventHost::poll_and_dispatch(
  self : MomEventHost,
  runtime : MomEventWorkspaceRuntime,
  adapter : T,
  mom : MomAgent,
  now : String
) -> Result[Array[MomEventDispatchResult], MomEventDispatchError] {
  let plans = match self.poll(runtime, now) {
    Ok(value) => value
    Err(message) => return Err(RuntimeFailed(message))
  }
  let results : Array[MomEventDispatchResult] = []
  for plan in plans {
    match dispatch_mom_event_plan_with_adapter(adapter, mom, plan, now) {
      Ok(result) => results.push(result)
      Err(error) => return Err(error)
    }
  }
  Ok(results)
}

pub fn[T : PlatformAdapter] MomEventHost::poll_dispatch_and_cleanup(
  self : MomEventHost,
  runtime : MomEventWorkspaceRuntime,
  adapter : T,
  mom : MomAgent,
  now : String
) -> Result[Array[MomEventDispatchResult], MomEventDispatchError] {
  let plans = match self.poll(runtime, now) {
    Ok(value) => value
    Err(message) => return Err(RuntimeFailed(message))
  }
  let results : Array[MomEventDispatchResult] = []
  let cleanup_filenames : Array[String] = []
  for plan in plans {
    match dispatch_mom_event_plan_with_adapter(adapter, mom, plan, now) {
      Ok(result) => {
        results.push(result)
        match mom_event_plan_cleanup_filename(plan) {
          Some(filename) => cleanup_filenames.push(filename)
          None => ()
        }
      }
      Err(error) => return Err(error)
    }
  }
  for filename in cleanup_filenames {
    let path = workspace_event_file_path(self.workspace_dir, filename)
    match (runtime.delete_file)(path) {
      Ok(_) => ()
      Err(message) => return Err(RuntimeFailed(message))
    }
  }
  Ok(results)
}

pub fn load_workspace_mom_event_files(
  runtime : MomEventWorkspaceRuntime,
  workspace_dir : String
) -> Result[Array[MomEventFile], String] {
  let events_dir = workspace_events_dir(workspace_dir)
  let paths = match (runtime.list_files)(events_dir) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let files : Array[MomEventFile] = []
  for listed_path in paths {
    let filename = mom_event_filename(events_dir, listed_path)
    if !filename.has_suffix(".json") {
      continue
    }
    let path = mom_event_file_path(workspace_dir, events_dir, listed_path, filename)
    let content = match (runtime.read_text)(path) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    let modified_at = match (runtime.read_modified_at)(path) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    files.push({ filename, content, modified_at })
  }
  Ok(sort_mom_event_files(files))
}

pub fn plan_workspace_mom_events(
  runtime : MomEventWorkspaceRuntime,
  workspace_dir : String,
  started_at : String,
  now : String
) -> Result[Array[MomEventPlan], String] {
  let files = match load_workspace_mom_event_files(runtime, workspace_dir) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  plan_mom_events(files, started_at, now)
}

pub fn event_trigger_to_channel_message(
  trigger : MomEventTrigger,
  adapter_name : String,
  timestamp : String
) -> Result[ChannelMessage, MomEventDispatchError] {
  let qualified_channel_id = mom_event_channel_id(trigger.event)
  let (event_adapter, channel_id) = match parse_qualified_channel_id(qualified_channel_id) {
    Some(value) => value
    None => return Err(InvalidChannelId(qualified_channel_id))
  }
  if event_adapter != adapter_name {
    return Err(
      AdapterMismatch(
        "event targets adapter " + event_adapter + " but runtime adapter is " + adapter_name,
      ),
    )
  }

  Ok({
    id: "event-" + mom_event_dispatch_safe_id(trigger.filename + "-" + timestamp),
    channel_id,
    timestamp,
    sender: {
      id: "event",
      username: "event",
      display_name: Some("event"),
      is_bot: false,
    },
    text: trigger.message,
    raw_text: Some(trigger.message),
    attachments: [],
    is_mention: false,
    reply_to: None,
    metadata: Some(Json::object({
      "kind": Json::string("mom-event"),
      "filename": Json::string(trigger.filename),
      "deleteAfter": Json::boolean(trigger.delete_after),
    })),
  })
}

pub fn[T : PlatformAdapter] dispatch_mom_event_plan_with_adapter(
  adapter : T,
  mom : MomAgent,
  plan : MomEventPlan,
  timestamp : String
) -> Result[MomEventDispatchResult, MomEventDispatchError] {
  match plan {
    Trigger(trigger) => {
      let message = match event_trigger_to_channel_message(trigger, adapter.name(), timestamp) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      match run_mom_turn_with_adapter(adapter, mom, message) {
        Ok(result) => Ok(Triggered(result))
        Err(error) => Err(AgentFailed(error))
      }
    }
    ScheduleOneShot(value) => Ok(ScheduledOneShot(value))
    RegisterPeriodic(value) => Ok(RegisteredPeriodic(value))
    Delete(filename) => Ok(Deleted(filename))
    Invalid(filename, message) => Ok(Invalid(filename, message))
  }
}

fn MomEventHost::update_plans(
  self : MomEventHost,
  plans : Array[MomEventPlan]
) -> Array[MomEventPlan] {
  let changed : Array[MomEventPlan] = []
  let next_observed : Array[(String, MomEventPlan)] = []
  let next_scheduled : Array[MomScheduledOneShot] = []
  let next_periodic : Array[MomRegisteredPeriodic] = []

  for plan in plans {
    let filename = mom_event_plan_filename(plan)
    let previous = find_observed_plan(self.observed_plans, filename)
    match previous {
      Some(value) if value == plan => ()
      _ => changed.push(plan)
    }
    next_observed.push((filename, plan))
    match plan {
      ScheduleOneShot(value) => next_scheduled.push(value)
      RegisterPeriodic(value) => next_periodic.push(value)
      _ => ()
    }
  }

  self.observed_plans = next_observed
  self.scheduled_one_shots = next_scheduled
  self.registered_periodics = next_periodic
  changed
}

fn mom_event_filename(events_dir : String, listed_path : String) -> String {
  let prefix = if events_dir.has_suffix("/") {
    events_dir
  } else {
    events_dir + "/"
  }
  if listed_path.has_prefix(prefix) {
    listed_path[prefix.length():].to_string()
  } else {
    listed_path
  }
}

fn mom_event_file_path(
  workspace_dir : String,
  events_dir : String,
  listed_path : String,
  filename : String
) -> String {
  let prefix = if events_dir.has_suffix("/") {
    events_dir
  } else {
    events_dir + "/"
  }
  if listed_path.has_prefix(prefix) {
    listed_path
  } else {
    workspace_event_file_path(workspace_dir, filename)
  }
}

fn sort_mom_event_files(files : Array[MomEventFile]) -> Array[MomEventFile] {
  let mut remaining = files.copy()
  let sorted : Array[MomEventFile] = []
  while remaining.length() > 0 {
    let first_index = earliest_mom_event_file_index(remaining)
    sorted.push(remaining[first_index])
    remaining = filter_mom_event_files_by_index(remaining, first_index)
  }
  sorted
}

fn earliest_mom_event_file_index(files : Array[MomEventFile]) -> Int {
  let mut earliest_index = 0
  for i in 1..<files.length() {
    if files[i].filename < files[earliest_index].filename {
      earliest_index = i
    }
  }
  earliest_index
}

fn filter_mom_event_files_by_index(
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

fn mom_event_dispatch_safe_id(value : String) -> String {
  value
    .replace_all(old="/", new="-")
    .replace_all(old=":", new="-")
    .replace_all(old=" ", new="-")
    .replace_all(old=".", new="-")
}

fn find_observed_plan(
  observed_plans : Array[(String, MomEventPlan)],
  filename : String
) -> MomEventPlan? {
  for item in observed_plans {
    let (existing_filename, plan) = item
    if existing_filename == filename {
      return Some(plan)
    }
  }
  None
}

fn mom_event_plan_filename(plan : MomEventPlan) -> String {
  match plan {
    Trigger(value) => value.filename
    ScheduleOneShot(value) => value.filename
    RegisterPeriodic(value) => value.filename
    Delete(filename) => filename
    Invalid(filename, _message) => filename
  }
}

fn mom_event_plan_cleanup_filename(plan : MomEventPlan) -> String? {
  match plan {
    Trigger(value) if value.delete_after => Some(value.filename)
    Delete(filename) => Some(filename)
    Invalid(filename, _message) => Some(filename)
    _ => None
  }
}
