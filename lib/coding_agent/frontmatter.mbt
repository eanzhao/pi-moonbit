///| YAML frontmatter 解析（极简：仅支持扁平 key: value）。

pub(all) struct FrontmatterResult {
  metadata : Map[String, String]
  body : String
}

///| 解析带 `---` 分隔符的 frontmatter。
///
/// ```
/// ---
/// name: My Skill
/// description: Does X
/// ---
/// Body content here
/// ```
pub fn parse_frontmatter(text : String) -> FrontmatterResult {
  if !text.has_prefix("---\n") && !text.has_prefix("---\r\n") {
    return { metadata: {}, body: text }
  }
  let lines : Array[String] = []
  for line in text.split("\n") {
    lines.push(line.to_string())
  }
  if lines.length() < 2 {
    return { metadata: {}, body: text }
  }
  // Find closing ---
  let mut closing_index = -1
  let mut i = 1
  while i < lines.length() {
    let line = trim_cr(lines[i])
    if line == "---" {
      closing_index = i
      break
    }
    i = i + 1
  }
  if closing_index < 0 {
    return { metadata: {}, body: text }
  }
  let metadata : Map[String, String] = {}
  let mut j = 1
  while j < closing_index {
    let line = trim_cr(lines[j])
    let colon = find_colon(line)
    if colon > 0 {
      let key = trim_string(line[:colon].to_string())
      let value = trim_string(line[colon + 1:].to_string())
      let unquoted = strip_quotes(value)
      metadata[key] = unquoted
    }
    j = j + 1
  }
  let body_lines : Array[String] = []
  let mut k = closing_index + 1
  while k < lines.length() {
    body_lines.push(lines[k])
    k = k + 1
  }
  { metadata, body: body_lines.join("\n") }
}

fn find_colon(line : String) -> Int {
  let mut i = 0
  while i < line.length() {
    if line[i] == ':' { return i }
    i = i + 1
  }
  -1
}

fn trim_string(s : String) -> String {
  let mut start = 0
  let mut end = s.length()
  while start < end && (s[start] == ' ' || s[start] == '\t') {
    start = start + 1
  }
  while end > start && (s[end - 1] == ' ' || s[end - 1] == '\t') {
    end = end - 1
  }
  s[start:end].to_string()
}

fn trim_cr(s : String) -> String {
  if s.has_suffix("\r") { s[:s.length() - 1].to_string() } else { s }
}

fn strip_quotes(s : String) -> String {
  if s.length() >= 2 {
    if (s.has_prefix("\"") && s.has_suffix("\"")) ||
       (s.has_prefix("'") && s.has_suffix("'")) {
      return s[1:s.length() - 1].to_string()
    }
  }
  s
}
