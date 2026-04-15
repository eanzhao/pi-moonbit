///| 最基础的多行文本组件。
pub(all) struct Text {
  mut content : String
  padding_x : Int
  padding_y : Int
}

///| 创建文本组件。
pub fn Text::new(
  content? : String = "",
  padding_x? : Int = 0,
  padding_y? : Int = 0
) -> Text {
  {
    content,
    padding_x: text_non_negative(padding_x),
    padding_y: text_non_negative(padding_y),
  }
}

///| 更新文本内容。
pub fn Text::set_text(self : Text, content : String) -> Unit {
  self.content = content
}

///| 读取当前文本内容。
pub fn Text::get_content(self : Text) -> String {
  self.content
}

pub impl Component for Text with render(self, width) {
  if width <= 0 {
    return []
  }

  let result : Array[String] = []
  let empty_line = spaces(width)
  let content_width = max_int(1, width - self.padding_x * 2)

  for i = 0; i < self.padding_y; i = i + 1 {
    result.push(empty_line)
  }

  let wrapped = wrap_text(self.content, content_width)
  for line in wrapped {
    let padded = spaces(self.padding_x) + line + spaces(self.padding_x)
    result.push(fit_to_width(padded, width))
  }

  for i = 0; i < self.padding_y; i = i + 1 {
    result.push(empty_line)
  }

  result
}

fn max_int(a : Int, b : Int) -> Int {
  if a > b { a } else { b }
}

fn text_non_negative(value : Int) -> Int {
  if value < 0 { 0 } else { value }
}
