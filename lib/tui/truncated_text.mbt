///| 单行截断文本组件。
/// 只渲染第一行内容，多余内容按宽度截断。
pub(all) struct TruncatedText {
  mut content : String
  padding_x : Int
  padding_y : Int
}

///| 创建单行截断文本组件。
pub fn TruncatedText::new(
  content? : String = "",
  padding_x? : Int = 0,
  padding_y? : Int = 0
) -> TruncatedText {
  {
    content,
    padding_x: truncated_text_non_negative(padding_x),
    padding_y: truncated_text_non_negative(padding_y),
  }
}

///| 更新文本内容。
pub fn TruncatedText::set_text(self : TruncatedText, content : String) -> Unit {
  self.content = content
}

pub impl Component for TruncatedText with render(self, width) {
  if width <= 0 {
    return []
  }

  let result : Array[String] = []
  let empty_line = spaces(width)
  let content_width = truncated_text_max_int(1, width - self.padding_x * 2)

  for i = 0; i < self.padding_y; i = i + 1 {
    result.push(empty_line)
  }

  let line = truncated_text_first_line(self.content)
  let fitted =
    spaces(self.padding_x) + truncate_to_width(line, content_width) + spaces(self.padding_x)
  result.push(fit_to_width(fitted, width))

  for i = 0; i < self.padding_y; i = i + 1 {
    result.push(empty_line)
  }

  result
}

fn truncated_text_first_line(content : String) -> String {
  let chars : Array[Char] = []
  for ch in content.iter() {
    if ch == '\n' || ch == '\r' {
      break
    }
    chars.push(ch)
  }
  String::from_array(chars[:])
}

fn truncated_text_max_int(a : Int, b : Int) -> Int {
  if a > b { a } else { b }
}

fn truncated_text_non_negative(value : Int) -> Int {
  if value < 0 { 0 } else { value }
}
