pub fn format_cost(cost : Double) -> String {
  "$" + format_fixed_decimal(cost, 4)
}

pub fn format_model_cost(cost : @ai.ModelCost) -> String {
  if cost.input == 0.0 && cost.output == 0.0 {
    return "Free"
  }
  "$" + format_model_rate(cost.input) + "/$" + format_model_rate(cost.output)
}

pub fn format_usage(usage : @ai.Usage) -> String {
  let parts : Array[String] = []
  if usage.input > 0 {
    parts.push("↑" + format_token_count(usage.input))
  }
  if usage.output > 0 {
    parts.push("↓" + format_token_count(usage.output))
  }
  if usage.cache_read > 0 {
    parts.push("R" + format_token_count(usage.cache_read))
  }
  if usage.cache_write > 0 {
    parts.push("W" + format_token_count(usage.cache_write))
  }
  if usage.cost.total > 0.0 {
    parts.push(format_cost(usage.cost.total))
  }
  parts.join(" ")
}

pub fn format_token_count(count : Int) -> String {
  if count < 1000 {
    count.to_string()
  } else if count < 10000 {
    format_fixed_decimal(count.to_double() / 1000.0, 1) + "k"
  } else {
    ((count + 500) / 1000).to_string() + "k"
  }
}

pub fn format_relative_date(iso_string : String, today_iso : String) -> String {
  let target = match parse_iso_day(iso_string) {
    Some(value) => value
    None => return iso_string
  }
  let today = match parse_iso_day(today_iso) {
    Some(value) => value
    None => return iso_string
  }
  let day_diff = iso_day_ordinal(today) - iso_day_ordinal(target)
  if day_diff == 0 {
    "Today"
  } else if day_diff == 1 {
    "Yesterday"
  } else if day_diff > 1 && day_diff < 7 {
    day_diff.to_string() + " days ago"
  } else if iso_string.length() >= 10 {
    iso_string[:10].to_string()
  } else {
    iso_string
  }
}

priv struct IsoDay {
  year : Int
  month : Int
  day : Int
}

fn format_model_rate(value : Double) -> String {
  if value >= 100.0 {
    format_fixed_decimal(value, 0)
  } else if value >= 10.0 {
    trim_decimal_zeros(format_fixed_decimal(value, 1))
  } else if value >= 1.0 {
    trim_decimal_zeros(format_fixed_decimal(value, 2))
  } else {
    trim_decimal_zeros(format_fixed_decimal(value, 3))
  }
}

fn format_fixed_decimal(value : Double, digits : Int) -> String {
  let negative = value < 0.0
  let scale = decimal_scale(digits)
  let rounded = (if negative { (-value) * scale.to_double() + 0.5 } else { value * scale.to_double() + 0.5 }).to_int()
  let integer_part = rounded / scale
  let fraction_part = rounded % scale
  let integer_text = integer_part.to_string()
  if digits == 0 {
    if negative { "-" + integer_text } else { integer_text }
  } else {
    let fraction_text = fraction_part.to_string().pad_start(digits, '0')
    if negative {
      "-" + integer_text + "." + fraction_text
    } else {
      integer_text + "." + fraction_text
    }
  }
}

fn decimal_scale(digits : Int) -> Int {
  let mut scale = 1
  for _i in 0..<digits {
    scale = scale * 10
  }
  scale
}

fn trim_decimal_zeros(text : String) -> String {
  if text.contains(".") {
    let mut result = text
    while result.has_suffix("0") {
      result = result[:result.length() - 1].to_string()
    }
    if result.has_suffix(".") {
      result[:result.length() - 1].to_string()
    } else {
      result
    }
  } else {
    text
  }
}

fn parse_iso_day(iso_string : String) -> IsoDay? {
  if iso_string.length() < 10 {
    return None
  }
  let year = try @string.parse_int(iso_string[:4].to_string()) catch {
    _error => return None
  } noraise {
    value => value
  }
  let month = try @string.parse_int(iso_string[5:7].to_string()) catch {
    _error => return None
  } noraise {
    value => value
  }
  let day = try @string.parse_int(iso_string[8:10].to_string()) catch {
    _error => return None
  } noraise {
    value => value
  }
  Some({ year, month, day })
}

fn iso_day_ordinal(day : IsoDay) -> Int {
  let adjusted_year = if day.month <= 2 { day.year - 1 } else { day.year }
  let adjusted_month = if day.month <= 2 { day.month + 12 } else { day.month }
  let era = adjusted_year / 400
  let year_of_era = adjusted_year - era * 400
  let month_offset = ((153 * (adjusted_month - 3)) + 2) / 5
  let day_of_year = month_offset + day.day - 1
  let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year
  era * 146097 + day_of_era
}
