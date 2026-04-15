///| 空白占位组件，用于插入若干空行。
pub(all) struct Spacer {
  mut line_count : Int
}

///| 创建 Spacer。
pub fn Spacer::new(line_count? : Int = 1) -> Spacer {
  { line_count: spacer_non_negative(line_count) }
}

///| 更新空行数量。
pub fn Spacer::set_line_count(self : Spacer, line_count : Int) -> Unit {
  self.line_count = spacer_non_negative(line_count)
}

pub impl Component for Spacer with render(_self, _width) {
  let lines : Array[String] = []
  for i = 0; i < _self.line_count; i = i + 1 {
    lines.push("")
  }
  lines
}

fn spacer_non_negative(value : Int) -> Int {
  if value < 0 { 0 } else { value }
}
