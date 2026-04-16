pub fn parse_mom_event_json(text : String) -> Result[MomEvent, String] {
  let json = try @json.parse(text) catch {
    _error => return Err("event must be valid JSON")
  } noraise {
    value => value
  }
  mom_event_from_json(json)
}

pub fn mom_event_from_json(json : Json) -> Result[MomEvent, String] {
  let type_name = match mom_event_json_string_field_any(json, ["type"]) {
    Some(value) => value
    None => return Err("event is missing type")
  }
  let channel_id = match mom_event_json_string_field_any(json, ["channelId", "channel_id"]) {
    Some(value) => value
    None => return Err("event is missing channelId")
  }
  let text = match mom_event_json_string_field_any(json, ["text"]) {
    Some(value) => value
    None => return Err("event is missing text")
  }

  match normalized_event_type(type_name) {
    Some("immediate") => Ok(MomEvent::Immediate({ channel_id, text }))
    Some("one-shot") =>
      match mom_event_json_string_field_any(json, ["at"]) {
        Some(at) => Ok(MomEvent::OneShot({ channel_id, text, at }))
        None => Err("one-shot event is missing at")
      }
    Some("periodic") => {
      let schedule = match mom_event_json_string_field_any(json, ["schedule"]) {
        Some(value) => value
        None => return Err("periodic event is missing schedule")
      }
      let timezone = match mom_event_json_string_field_any(json, ["timezone"]) {
        Some(value) => value
        None => return Err("periodic event is missing timezone")
      }
      Ok(MomEvent::Periodic({ channel_id, text, schedule, timezone }))
    }
    _ => Err("unknown event type: " + type_name)
  }
}

pub fn mom_event_to_json(event : MomEvent) -> Json {
  match event {
    Immediate(value) =>
      Json::object({
        "type": Json::string("immediate"),
        "channelId": Json::string(value.channel_id),
        "text": Json::string(value.text),
      })
    OneShot(value) =>
      Json::object({
        "type": Json::string("one-shot"),
        "channelId": Json::string(value.channel_id),
        "text": Json::string(value.text),
        "at": Json::string(value.at),
      })
    Periodic(value) =>
      Json::object({
        "type": Json::string("periodic"),
        "channelId": Json::string(value.channel_id),
        "text": Json::string(value.text),
        "schedule": Json::string(value.schedule),
        "timezone": Json::string(value.timezone),
      })
  }
}

pub fn mom_event_file_text(event : MomEvent) -> String {
  mom_event_to_json(event).stringify(escape_slash=false)
}

pub fn mom_event_channel_id(event : MomEvent) -> String {
  match event {
    Immediate(value) => value.channel_id
    OneShot(value) => value.channel_id
    Periodic(value) => value.channel_id
  }
}

pub fn mom_event_type_name(event : MomEvent) -> String {
  match event {
    Immediate(_) => "immediate"
    OneShot(_) => "one-shot"
    Periodic(_) => "periodic"
  }
}

pub fn mom_event_schedule_text(event : MomEvent) -> String? {
  match event {
    Immediate(_) => None
    OneShot(value) => Some(value.at)
    Periodic(value) => Some(value.schedule)
  }
}

pub fn build_event_trigger_message(filename : String, event : MomEvent) -> String {
  let prefix = "[EVENT:" + filename + ":" + mom_event_type_name(event)
  let suffix = match mom_event_schedule_text(event) {
    Some(value) => ":" + value
    None => ""
  }
  prefix + suffix + "] " + mom_event_text(event)
}

fn mom_event_text(event : MomEvent) -> String {
  match event {
    Immediate(value) => value.text
    OneShot(value) => value.text
    Periodic(value) => value.text
  }
}

fn normalized_event_type(value : String) -> String? {
  match value {
    "immediate" => Some("immediate")
    "one-shot" => Some("one-shot")
    "one_shot" => Some("one-shot")
    "oneshot" => Some("one-shot")
    "periodic" => Some("periodic")
    _ => None
  }
}

fn mom_event_json_string_field_any(json : Json, keys : Array[String]) -> String? {
  for key in keys {
    if json is Object(obj) {
      match obj.get(key) {
        Some(String(value)) => return Some(value)
        _ => ()
      }
    }
  }
  None
}
