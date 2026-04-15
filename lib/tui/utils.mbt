///| 计算字符串在终端中的可见宽度。
/// 当前实现采用简化规则：普通字符宽度为 1，Tab 宽度为 4。
pub fn visible_width(text : String) -> Int {
  let mut width = 0
  for ch in text.iter() {
    width = width + char_width(ch)
  }
  width
}

///| 生成指定数量的空格。
pub fn spaces(count : Int) -> String {
  if count <= 0 {
    return ""
  }
  let chars = Array::make(count, ' ')
  String::from_array(chars[:])
}

///| 把一行文本裁剪到指定宽度。
pub fn truncate_to_width(text : String, width : Int) -> String {
  if width <= 0 {
    return ""
  }
  let chars : Array[Char] = []
  let mut used = 0
  for ch in text.iter() {
    let w = char_width(ch)
    if used + w > width {
      break
    }
    chars.push(ch)
    used = used + w
  }
  String::from_array(chars[:])
}

///| 把一行文本补齐到指定宽度。
pub fn pad_right(text : String, width : Int) -> String {
  let padding = width - visible_width(text)
  if padding <= 0 {
    text
  } else {
    text + spaces(padding)
  }
}

///| 先裁剪再补齐，确保结果行宽恰好等于目标宽度。
pub fn fit_to_width(text : String, width : Int) -> String {
  pad_right(truncate_to_width(text, width), width)
}

///| 按固定宽度对文本进行硬换行。
/// `\n` 会强制换行，`\r` 会被忽略。
pub fn wrap_text(text : String, width : Int) -> Array[String] {
  let width = if width <= 0 { 1 } else { width }
  let lines : Array[String] = []
  let current : Array[Char] = []
  let mut current_width = 0

  for ch in text.iter() {
    if ch == '\r' {
      continue
    }
    if ch == '\n' {
      lines.push(String::from_array(current[:]))
      current.clear()
      current_width = 0
      continue
    }

    let w = char_width(ch)
    if current_width + w > width && !current.is_empty() {
      lines.push(String::from_array(current[:]))
      current.clear()
      current_width = 0
    }

    current.push(ch)
    current_width = current_width + w

    if current_width >= width {
      lines.push(String::from_array(current[:]))
      current.clear()
      current_width = 0
    }
  }

  if !current.is_empty() || lines.is_empty() {
    lines.push(String::from_array(current[:]))
  }

  lines
}

fn char_width(ch : Char) -> Int {
  if ch == '\t' {
    4
  } else {
    1
  }
}
