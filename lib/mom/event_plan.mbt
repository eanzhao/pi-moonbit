pub fn plan_mom_event(
  file : MomEventFile,
  started_at : String,
  now : String
) -> Result[MomEventPlan, String] {
  let started_ms = match parse_mom_timestamp_ms(started_at) {
    Ok(value) => value
    Err(message) => return Err("invalid started_at: " + message)
  }
  let now_ms = match parse_mom_timestamp_ms(now) {
    Ok(value) => value
    Err(message) => return Err("invalid now: " + message)
  }
  match parse_mom_event_json(file.content) {
    Ok(event) => Ok(plan_loaded_mom_event(file, event, started_ms, now_ms))
    Err(message) => Ok(Invalid(file.filename, message))
  }
}

pub fn plan_mom_events(
  files : Array[MomEventFile],
  started_at : String,
  now : String
) -> Result[Array[MomEventPlan], String] {
  let plans : Array[MomEventPlan] = []
  for file in files {
    match plan_mom_event(file, started_at, now) {
      Ok(plan) => plans.push(plan)
      Err(message) => return Err(message)
    }
  }
  Ok(plans)
}

fn plan_loaded_mom_event(
  file : MomEventFile,
  event : MomEvent,
  started_ms : UInt64,
  now_ms : UInt64
) -> MomEventPlan {
  match event {
    Immediate(_) =>
      if mom_is_stale_immediate_event(file.modified_at, started_ms) {
        Delete(file.filename)
      } else {
        Trigger({
          filename: file.filename,
          event,
          message: build_event_trigger_message(file.filename, event),
          delete_after: true,
        })
      }
    OneShot(value) =>
      match parse_mom_timestamp_ms(value.at) {
        Ok(at_ms) =>
          if at_ms <= now_ms {
            Trigger({
              filename: file.filename,
              event,
              message: build_event_trigger_message(file.filename, event),
              delete_after: true,
            })
          } else {
            ScheduleOneShot({ filename: file.filename, event: value })
          }
        Err(message) => Invalid(file.filename, message)
      }
    Periodic(value) => RegisterPeriodic({ filename: file.filename, event: value })
  }
}

fn mom_is_stale_immediate_event(
  modified_at : String?,
  started_ms : UInt64
) -> Bool {
  match modified_at {
    Some(value) =>
      match parse_mom_timestamp_ms(value) {
        Ok(modified_ms) => modified_ms < started_ms
        Err(_) => false
      }
    None => false
  }
}
