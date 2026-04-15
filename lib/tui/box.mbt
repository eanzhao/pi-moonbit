///| 带内边距的容器组件。
/// 当前版本支持对子组件统一加 padding，并可选地对整行应用背景函数。
pub(all) struct Box {
  mut container : Container
  padding_x : Int
  padding_y : Int
  mut bg_fn : ((String) -> String)?
}

///| 创建 Box。
pub fn Box::new(
  padding_x? : Int = 1,
  padding_y? : Int = 1,
  bg_fn? : ((String) -> String)? = None
) -> Box {
  {
    container: Container::new(),
    padding_x: box_non_negative(padding_x),
    padding_y: box_non_negative(padding_y),
    bg_fn,
  }
}

///| 添加子组件。
pub fn Box::add_child(self : Box, component : &Component) -> ComponentHandle {
  self.container.add_child(component)
}

///| 删除子组件。
pub fn Box::remove_child(self : Box, handle : ComponentHandle) -> Unit {
  self.container.remove_child(handle)
}

///| 清空子组件。
pub fn Box::clear(self : Box) -> Unit {
  self.container.clear()
}

///| 设置背景函数。
pub fn Box::set_bg_fn(self : Box, bg_fn : ((String) -> String)?) -> Unit {
  self.bg_fn = bg_fn
}

pub impl Component for Box with render(self, width) {
  if self.container.child_count() == 0 {
    return []
  }

  let content_width = box_max_int(1, width - self.padding_x * 2)
  let result : Array[String] = []
  let empty_line = box_apply_background(self, spaces(width))
  let left_padding = spaces(self.padding_x)

  for i = 0; i < self.padding_y; i = i + 1 {
    result.push(empty_line)
  }

  let child_lines = self.container.render(content_width)
  for line in child_lines {
    let padded = fit_to_width(left_padding + line, width)
    result.push(box_apply_background(self, padded))
  }

  for i = 0; i < self.padding_y; i = i + 1 {
    result.push(empty_line)
  }

  result
}

pub impl Component for Box with invalidate(self) {
  self.container.invalidate()
}

pub impl Component for Box with set_focused(self, focused) {
  self.container.set_focused(focused)
}

fn box_apply_background(box : Box, line : String) -> String {
  match box.bg_fn {
    Some(bg_fn) => bg_fn(line)
    None => line
  }
}

fn box_max_int(a : Int, b : Int) -> Int {
  if a > b { a } else { b }
}

fn box_non_negative(value : Int) -> Int {
  if value < 0 { 0 } else { value }
}
