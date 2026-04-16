pub fn render_markdown(text : String, width : Int) -> String {
  let lines : Array[String] = []
  let mut in_code_block = false

  for raw_line in text.split("\n") {
    let line = markdown_strip_cr(raw_line.to_string())
    if in_code_block {
      if line.has_prefix("```") {
        lines.push(markdown_dim_separator())
        in_code_block = false
      } else {
        lines.push(markdown_dim_line("  " + line))
      }
      continue
    }

    if line.has_prefix("```") {
      lines.push(markdown_dim_separator())
      in_code_block = true
    } else if line.has_prefix("# ") {
      lines.push(ansi_bold() + ansi_cyan() + line[2:].to_string() + ansi_reset())
    } else if line.has_prefix("## ") {
      lines.push(ansi_bold() + ansi_blue() + line[3:].to_string() + ansi_reset())
    } else if line.has_prefix("### ") {
      lines.push(ansi_bold() + line[4:].to_string() + ansi_reset())
    } else if line == "- " || line.has_prefix("- ") {
      lines.push("  • " + render_markdown_inline(line[2:].to_string()))
    } else if line == "* " || line.has_prefix("* ") {
      lines.push("  • " + render_markdown_inline(line[2:].to_string()))
    } else if markdown_is_horizontal_rule(line) {
      lines.push(markdown_dim_line(markdown_horizontal_rule(width)))
    } else if line.has_prefix("> ") {
      lines.push(markdown_dim_line("│ " + render_markdown_inline(line[2:].to_string())))
    } else if line.has_prefix(">") {
      lines.push(markdown_dim_line("│ " + render_markdown_inline(line[1:].to_string())))
    } else {
      match markdown_ordered_list_item(line) {
        Some((prefix, content)) =>
          lines.push("  " + prefix + render_markdown_inline(content))
        None => lines.push(render_markdown_inline(line))
      }
    }
  }

  lines.join("\n")
}

pub fn render_markdown_inline(text : String) -> String {
  let chars = markdown_chars(text)
  let parts : Array[String] = []
  let mut index = 0

  while index < chars.length() {
    if chars[index] == '`' {
      match markdown_find_inline_code_end(chars, index + 1) {
        Some(end) if end > index + 1 => {
          parts.push(
            ansi_yellow() +
            String::from_array(chars[index + 1:end]) +
            ansi_reset(),
          )
          index = end + 1
          continue
        }
        _ => ()
      }
    }

    if markdown_is_bold_marker(chars, index) {
      match markdown_find_bold_end(chars, index + 2) {
        Some(end) if end > index + 2 => {
          parts.push(
            ansi_bold() +
            String::from_array(chars[index + 2:end]) +
            ansi_reset(),
          )
          index = end + 2
          continue
        }
        _ => ()
      }
    }

    if markdown_is_italic_marker(chars, index) {
      match markdown_find_italic_end(chars, index + 1) {
        Some(end) if end > index + 1 => {
          parts.push(
            markdown_italic_seq() +
            String::from_array(chars[index + 1:end]) +
            ansi_reset(),
          )
          index = end + 1
          continue
        }
        _ => ()
      }
    }

    parts.push(markdown_char_string(chars[index]))
    index = index + 1
  }

  parts.join("")
}

fn markdown_strip_cr(text : String) -> String {
  if text.has_suffix("\r") && text.length() > 0 {
    text[:text.length() - 1].to_string()
  } else {
    text
  }
}

fn markdown_chars(text : String) -> Array[Char] {
  let chars : Array[Char] = []
  for ch in text.iter() {
    chars.push(ch)
  }
  chars
}

fn markdown_char_string(ch : Char) -> String {
  let chars : Array[Char] = []
  chars.push(ch)
  String::from_array(chars[:])
}

fn markdown_find_inline_code_end(chars : Array[Char], start : Int) -> Int? {
  let mut index = start
  while index < chars.length() {
    if chars[index] == '`' {
      return Some(index)
    }
    index = index + 1
  }
  None
}

fn markdown_is_bold_marker(chars : Array[Char], index : Int) -> Bool {
  index + 1 < chars.length() && chars[index] == '*' && chars[index + 1] == '*'
}

fn markdown_find_bold_end(chars : Array[Char], start : Int) -> Int? {
  let mut index = start
  while index + 1 < chars.length() {
    if chars[index] == '*' && chars[index + 1] == '*' {
      return Some(index)
    }
    index = index + 1
  }
  None
}

fn markdown_is_italic_marker(chars : Array[Char], index : Int) -> Bool {
  chars[index] == '*' &&
  (index == 0 || chars[index - 1] != '*') &&
  (index + 1 >= chars.length() || chars[index + 1] != '*')
}

fn markdown_find_italic_end(chars : Array[Char], start : Int) -> Int? {
  let mut index = start
  while index < chars.length() {
    if chars[index] == '*' &&
      (index == 0 || chars[index - 1] != '*') &&
      (index + 1 >= chars.length() || chars[index + 1] != '*') {
      return Some(index)
    }
    index = index + 1
  }
  None
}

fn markdown_italic_seq() -> String { "\u{1b}[3m" }

fn markdown_dim_line(text : String) -> String {
  ansi_dim() + text + ansi_reset()
}

fn markdown_dim_separator() -> String {
  markdown_dim_line("───")
}

fn markdown_is_horizontal_rule(line : String) -> Bool {
  let trimmed = line.trim()
  trimmed == "---" || trimmed == "***"
}

fn markdown_horizontal_rule(width : Int) -> String {
  let line_width = if width < 3 { 3 } else { width }
  String::from_array(Array::make(line_width, '─')[:])
}

fn markdown_ordered_list_item(line : String) -> (String, String)? {
  let chars = markdown_chars(line)
  let mut index = 0
  while index < chars.length() && markdown_is_ascii_digit(chars[index]) {
    index = index + 1
  }

  if index == 0 || index + 1 >= chars.length() || chars[index] != '.' || chars[index + 1] != ' ' {
    return None
  }

  Some((
    String::from_array(chars[:index + 2]),
    String::from_array(chars[index + 2:]),
  ))
}

fn markdown_is_ascii_digit(ch : Char) -> Bool {
  let code = ch.to_int()
  code >= '0'.to_int() && code <= '9'.to_int()
}
