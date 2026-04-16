pub fn plan_mom_event(
  file : MomEventFile,
  started_at : String,
  now : String
) -> Result[MomEventPlan, String] {
  let started_ms = match mom_parse_iso_timestamp_ms(started_at) {
    Ok(value) => value
    Err(message) => return Err("invalid started_at: " + message)
  }
  let now_ms = match mom_parse_iso_timestamp_ms(now) {
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
      match mom_parse_iso_timestamp_ms(value.at) {
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
      match mom_parse_iso_timestamp_ms(value) {
        Ok(modified_ms) => modified_ms < started_ms
        Err(_) => false
      }
    None => false
  }
}

fn mom_parse_iso_timestamp_ms(text : String) -> Result[UInt64, String] {
  if text.length() < 20 {
    return Err("timestamp is too short")
  }

  let year = match mom_parse_iso_segment(text, 0, 4, "year") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let month = match mom_parse_iso_segment(text, 5, 7, "month") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let day = match mom_parse_iso_segment(text, 8, 10, "day") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let hour = match mom_parse_iso_segment(text, 11, 13, "hour") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let minute = match mom_parse_iso_segment(text, 14, 16, "minute") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let second = match mom_parse_iso_segment(text, 17, 19, "second") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let timezone_start = match mom_timezone_start_index(text) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let fractional_ms = match mom_parse_fractional_millis(text, timezone_start) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let day_count = match mom_days_since_unix_epoch(year, month, day) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let day_ms = day_count.to_uint64() * 86_400_000UL
  let clock_ms =
    hour.to_uint64() * 3_600_000UL +
    minute.to_uint64() * 60_000UL +
    second.to_uint64() * 1_000UL +
    fractional_ms
  let naive_ms = day_ms + clock_ms
  let offset_ms = match mom_parse_timezone_offset_ms(text, timezone_start) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  match offset_ms {
    Some((sign, value)) =>
      if sign > 0 {
        if naive_ms < value {
          Err("timestamp is before unix epoch")
        } else {
          Ok(naive_ms - value)
        }
      } else {
        Ok(naive_ms + value)
      }
    None => Ok(naive_ms)
  }
}

fn mom_parse_iso_segment(
  text : String,
  start : Int,
  end_ : Int,
  label : String
) -> Result[Int, String] {
  let segment = text[start:end_].to_string()
  let parsed : Result[Int, Error] = try? @string.parse_int(segment)
  match parsed {
    Ok(value) => Ok(value)
    Err(_) => Err("invalid " + label + " in timestamp")
  }
}

fn mom_timezone_start_index(text : String) -> Result[Int, String] {
  if text.has_suffix("Z") {
    Ok(text.length() - 1)
  } else if text.length() >= 6 {
    let sign = text.unsafe_get(text.length() - 6).to_int()
    if sign == '+'.to_int() || sign == '-'.to_int() {
      Ok(text.length() - 6)
    } else {
      Err("timestamp is missing timezone")
    }
  } else {
    Err("timestamp is missing timezone")
  }
}

fn mom_parse_fractional_millis(
  text : String,
  timezone_start : Int
) -> Result[UInt64, String] {
  if timezone_start == 19 {
    return Ok(0UL)
  }
  if timezone_start < 20 || text.unsafe_get(19).to_int() != '.'.to_int() {
    return Err("invalid fractional seconds in timestamp")
  }
  let digits = text[20:timezone_start].to_string()
  if digits.length() == 0 {
    return Err("invalid fractional seconds in timestamp")
  }

  let mut millis = 0UL
  let mut used = 0
  for i in 0..<digits.length() {
    let code = digits.unsafe_get(i).to_int()
    if code < '0'.to_int() || code > '9'.to_int() {
      return Err("invalid fractional seconds in timestamp")
    }
    if used < 3 {
      millis = millis * 10UL + (code - '0'.to_int()).to_uint64()
      used = used + 1
    }
  }
  while used < 3 {
    millis = millis * 10UL
    used = used + 1
  }
  Ok(millis)
}

fn mom_parse_timezone_offset_ms(
  text : String,
  timezone_start : Int
) -> Result[(Int, UInt64)?, String] {
  if timezone_start == text.length() - 1 && text.has_suffix("Z") {
    return Ok(None)
  }
  let sign_code = text.unsafe_get(timezone_start).to_int()
  let sign = if sign_code == '+'.to_int() {
    1
  } else if sign_code == '-'.to_int() {
    -1
  } else {
    return Err("invalid timezone offset in timestamp")
  }
  if text.length() - timezone_start != 6 || text.unsafe_get(timezone_start + 3).to_int() != ':'.to_int() {
    return Err("invalid timezone offset in timestamp")
  }
  let hour = match mom_parse_iso_segment(text, timezone_start + 1, timezone_start + 3, "timezone hour") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let minute = match mom_parse_iso_segment(text, timezone_start + 4, timezone_start + 6, "timezone minute") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let offset_ms = hour.to_uint64() * 3_600_000UL + minute.to_uint64() * 60_000UL
  Ok(Some((sign, offset_ms)))
}

fn mom_days_since_unix_epoch(year : Int, month : Int, day : Int) -> Result[Int, String] {
  if year < 1970 {
    return Err("timestamp is before unix epoch")
  }
  if month < 1 || month > 12 {
    return Err("invalid month in timestamp")
  }
  let month_lengths = mom_month_lengths(year)
  let max_day = month_lengths[month - 1]
  if day < 1 || day > max_day {
    return Err("invalid day in timestamp")
  }

  let mut days = 0
  for current_year in 1970..<year {
    let year_days = if mom_is_leap_year(current_year) { 366 } else { 365 }
    days = days + year_days
  }
  for i in 0..<(month - 1) {
    days = days + month_lengths[i]
  }
  Ok(days + day - 1)
}

fn mom_is_leap_year(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

fn mom_month_lengths(year : Int) -> Array[Int] {
  [
    31,
    if mom_is_leap_year(year) { 29 } else { 28 },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
}
