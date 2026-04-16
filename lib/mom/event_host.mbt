pub fn MomEventWorkspaceRuntime::new(
  read_text : (String) -> Result[String, String],
  list_files : (String) -> Result[Array[String], String],
  read_modified_at? : (String) -> Result[String?, String] = fn(_path) { Ok(None) }
) -> MomEventWorkspaceRuntime {
  { read_text, list_files, read_modified_at }
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
