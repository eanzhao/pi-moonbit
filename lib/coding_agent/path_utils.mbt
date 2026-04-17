///| 路径工具。

///| 规范化路径：合并重复斜杠，解析 `.` 和 `..`。
pub fn normalize_path(path : String) -> String {
  if path == "" { return "." }
  let is_absolute = path.has_prefix("/")
  let segments : Array[String] = []
  let mut current = ""
  for ch in path {
    if ch == '/' {
      if current.length() > 0 {
        process_segment(segments, current)
        current = ""
      }
    } else {
      current = current + ch.to_string()
    }
  }
  if current.length() > 0 {
    process_segment(segments, current)
  }
  if segments.length() == 0 {
    if is_absolute { "/" } else { "." }
  } else {
    let joined = segments.join("/")
    if is_absolute { "/" + joined } else { joined }
  }
}

fn process_segment(segments : Array[String], seg : String) -> Unit {
  if seg == "." || seg == "" {
    return
  }
  if seg == ".." {
    if segments.length() > 0 && segments[segments.length() - 1] != ".." {
      ignore(segments.pop())
    } else {
      segments.push("..")
    }
    return
  }
  segments.push(seg)
}

///| 判断路径是否绝对路径。
pub fn is_absolute_path(path : String) -> Bool {
  path.has_prefix("/") ||
  (path.length() >= 3 && path[1:3].to_string() == ":/") ||
  path.has_prefix("\\")
}

///| 拼接路径，处理分隔符。
pub fn join_path(base : String, child : String) -> String {
  if child.length() == 0 { return base }
  if is_absolute_path(child) { return child }
  if base.length() == 0 { return child }
  if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

///| 获取父目录路径。
pub fn parent_path(path : String) -> String? {
  if path == "/" || path == "" || path == "." {
    return None
  }
  let mut last_slash = -1
  let mut i = 0
  while i < path.length() {
    if path[i] == '/' && i < path.length() - 1 {
      last_slash = i
    }
    i = i + 1
  }
  if last_slash < 0 {
    if path.has_suffix("/") { None } else { Some(".") }
  } else if last_slash == 0 {
    Some("/")
  } else {
    Some(path[:last_slash].to_string())
  }
}

///| 获取文件名（路径最后一段）。
pub fn basename(path : String) -> String {
  if path == "" || path == "/" { return path }
  let trimmed = if path.has_suffix("/") {
    path[:path.length() - 1].to_string()
  } else {
    path
  }
  let mut last_slash = -1
  let mut i = 0
  while i < trimmed.length() {
    if trimmed[i] == '/' { last_slash = i }
    i = i + 1
  }
  if last_slash < 0 {
    trimmed
  } else {
    trimmed[last_slash + 1:].to_string()
  }
}

///| 获取文件扩展名（含点号），没有则返回空串。
pub fn extension(path : String) -> String {
  let name = basename(path)
  let mut last_dot = -1
  let mut i = 0
  while i < name.length() {
    if name[i] == '.' { last_dot = i }
    i = i + 1
  }
  if last_dot <= 0 {
    ""
  } else {
    name[last_dot:].to_string()
  }
}
