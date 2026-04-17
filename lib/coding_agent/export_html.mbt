pub fn export_session_html(
  messages : Array[@ai.Message],
  title : String,
  model : String,
  timestamp : String
) -> String {
  let body_parts : Array[String] = []
  for msg in messages {
    body_parts.push(render_message_html(msg))
  }
  let css = export_css()
  let header =
    "<div class=\"header\"><h1>" +
    html_escape(title) +
    "</h1><p>Model: " +
    html_escape(model) +
    " | " +
    html_escape(timestamp) +
    " | " +
    messages.length().to_string() +
    " messages</p></div>"
  "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>" +
  html_escape(title) +
  "</title><style>" +
  css +
  "</style></head><body>" +
  header +
  "<div class=\"messages\">" +
  body_parts.join("") +
  "</div></body></html>"
}

pub fn ansi_to_html(text : String) -> String {
  let mut result = ""
  let chars = export_chars(text)
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '\u{1b}' && i + 1 < chars.length() && chars[i + 1] == '[' {
      let mut j = i + 2
      while j < chars.length() && chars[j] != 'm' {
        j = j + 1
      }
      if j < chars.length() {
        let code = String::from_array(chars[i + 2:j])
        match code {
          "0" => result = result + "</span>"
          "1" => result = result + "<span style=\"font-weight:bold\">"
          "2" => result = result + "<span style=\"opacity:0.7\">"
          "3" => result = result + "<span style=\"font-style:italic\">"
          "31" => result = result + "<span style=\"color:#e74c3c\">"
          "32" => result = result + "<span style=\"color:#27ae60\">"
          "33" => result = result + "<span style=\"color:#f39c12\">"
          "34" => result = result + "<span style=\"color:#3498db\">"
          "35" => result = result + "<span style=\"color:#9b59b6\">"
          "36" => result = result + "<span style=\"color:#1abc9c\">"
          _ => ()
        }
        i = j + 1
        continue
      }
    }
    result = result + export_char_string(chars[i])
    i = i + 1
  }
  result
}

fn render_message_html(msg : @ai.Message) -> String {
  match msg {
    @ai.Message::User(u) =>
      "<div class=\"message user\"><strong>You</strong><div>" +
      render_content_html(u.content) +
      "</div></div>"
    @ai.Message::Assistant(a) =>
      "<div class=\"message assistant\"><strong>Assistant</strong><div>" +
      render_content_html(a.content) +
      "</div></div>"
    @ai.Message::ToolResult(t) => {
      let cls = if t.error { "tool error" } else { "tool" }
      "<div class=\"message " +
      cls +
      "\"><strong>Tool: " +
      html_escape(t.tool_name) +
      "</strong><pre>" +
      render_content_text(t.content) +
      "</pre></div>"
    }
  }
}

fn render_content_html(content : Array[@ai.ContentBlock]) -> String {
  let parts : Array[String] = []
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) => parts.push(markdown_to_html(text))
      @ai.ContentBlock::Thinking(text) =>
        parts.push("<details><summary>Thinking</summary><pre>" + html_escape(text) + "</pre></details>")
      @ai.ContentBlock::ToolCall(tc) =>
        parts.push("<div class=\"tool-call\">Tool call: <code>" + html_escape(tc.name) + "</code></div>")
      @ai.ContentBlock::Image(_) => parts.push("<em>[image]</em>")
    }
  }
  parts.join("")
}

fn render_content_text(content : Array[@ai.ContentBlock]) -> String {
  let parts : Array[String] = []
  for block in content {
    match block {
      @ai.ContentBlock::Text(t) => parts.push(html_escape(t))
      _ => ()
    }
  }
  parts.join("")
}

fn markdown_to_html(text : String) -> String {
  let lines : Array[String] = []
  let mut in_code = false
  for raw_line in text.split("\n") {
    let line = raw_line.to_string()
    if in_code {
      if line.has_prefix("```") {
        lines.push("</code></pre>")
        in_code = false
      } else {
        lines.push(html_escape(line))
      }
      continue
    }
    if line.has_prefix("```") {
      let lang = line[3:].to_string()
      lines.push("<pre><code class=\"language-" + html_escape(lang) + "\">")
      in_code = true
    } else if line.has_prefix("# ") {
      lines.push("<h2>" + inline_md_to_html(line[2:].to_string()) + "</h2>")
    } else if line.has_prefix("## ") {
      lines.push("<h3>" + inline_md_to_html(line[3:].to_string()) + "</h3>")
    } else if line.has_prefix("- ") {
      lines.push("<li>" + inline_md_to_html(line[2:].to_string()) + "</li>")
    } else {
      lines.push("<p>" + inline_md_to_html(line) + "</p>")
    }
  }
  lines.join("\n")
}

fn inline_md_to_html(text : String) -> String {
  let chars = export_chars(text)
  let parts : Array[String] = []
  let mut index = 0

  while index < chars.length() {
    if index + 1 < chars.length() && chars[index] == '*' && chars[index + 1] == '*' {
      match find_double_marker(chars, index + 2, '*') {
        Some(end) if end > index + 2 => {
          parts.push("<strong>" + html_escape(String::from_array(chars[index + 2:end])) + "</strong>")
          index = end + 2
          continue
        }
        _ => ()
      }
    }

    if chars[index] == '`' {
      match find_single_marker(chars, index + 1, '`') {
        Some(end) if end > index + 1 => {
          parts.push("<code>" + html_escape(String::from_array(chars[index + 1:end])) + "</code>")
          index = end + 1
          continue
        }
        _ => ()
      }
    }

    parts.push(html_escape(export_char_string(chars[index])))
    index = index + 1
  }

  parts.join("")
}

fn html_escape(text : String) -> String {
  let escaped_amp = text.replace(old="&", new="&amp;")
  let escaped_lt = escaped_amp.replace(old="<", new="&lt;")
  let escaped_gt = escaped_lt.replace(old=">", new="&gt;")
  escaped_gt.replace(old="\"", new="&quot;")
}

fn export_css() -> String {
  "body{font-family:system-ui,sans-serif;max-width:800px;margin:0 auto;padding:20px;background:#fafafa}.header{border-bottom:1px solid #ddd;padding-bottom:10px;margin-bottom:20px}.message{margin:12px 0;padding:12px;border-radius:8px}.user{background:#e3f2fd}.assistant{background:#f5f5f5}.tool{background:#fff8e1;font-size:0.9em}.error{border-left:3px solid #e74c3c}pre{background:#263238;color:#eee;padding:12px;border-radius:4px;overflow-x:auto}code{font-family:monospace;background:#eee;padding:2px 4px;border-radius:3px}pre code{background:none;padding:0}h2{color:#1a73e8}strong{font-weight:600}.tool-call{color:#666;font-size:0.9em}details summary{cursor:pointer;color:#666}"
}

fn export_chars(text : String) -> Array[Char] {
  let chars : Array[Char] = []
  for ch in text.iter() {
    chars.push(ch)
  }
  chars
}

fn export_char_string(ch : Char) -> String {
  let chars : Array[Char] = []
  chars.push(ch)
  String::from_array(chars[:])
}

fn find_single_marker(chars : Array[Char], start : Int, marker : Char) -> Int? {
  let mut index = start
  while index < chars.length() {
    if chars[index] == marker {
      return Some(index)
    }
    index = index + 1
  }
  None
}

fn find_double_marker(chars : Array[Char], start : Int, marker : Char) -> Int? {
  let mut index = start
  while index + 1 < chars.length() {
    if chars[index] == marker && chars[index + 1] == marker {
      return Some(index)
    }
    index = index + 1
  }
  None
}
