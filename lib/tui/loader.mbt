///| 简单加载指示器。
/// 通过 `tick()` 推进动画帧，不主动调度时间。
pub(all) struct Loader {
  mut frame_index : Int
  mut message : String
  padding_x : Int
}

///| 创建 Loader。
pub fn Loader::new(
  message? : String = "Loading...",
  padding_x? : Int = 1
) -> Loader {
  {
    frame_index: 0,
    message,
    padding_x: loader_non_negative(padding_x),
  }
}

///| 推进一步动画。
pub fn Loader::tick(self : Loader) -> Unit {
  self.frame_index = (self.frame_index + 1) % loader_frame_count()
}

///| 更新展示消息。
pub fn Loader::set_message(self : Loader, message : String) -> Unit {
  self.message = message
}

pub impl Component for Loader with render(self, width) {
  if width <= 0 {
    return []
  }
  let frame = loader_frame(self.frame_index)
  let line = spaces(self.padding_x) + frame + " " + self.message + spaces(self.padding_x)
  [fit_to_width(line, width)]
}

fn loader_frame(index : Int) -> String {
  match index {
    0 => "⠋"
    1 => "⠙"
    2 => "⠹"
    3 => "⠸"
    4 => "⠼"
    5 => "⠴"
    6 => "⠦"
    7 => "⠧"
    8 => "⠇"
    _ => "⠏"
  }
}

fn loader_frame_count() -> Int {
  10
}

fn loader_non_negative(value : Int) -> Int {
  if value < 0 { 0 } else { value }
}
