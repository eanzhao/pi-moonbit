///| TUI 主调度器。
/// 当前版本支持：
/// - 组件树渲染
/// - 基于行的差分 patch
/// - 聚焦组件输入转发
pub(all) struct TUI {
  terminal : &Terminal
  root : Container
  mut previous_frame : Array[String]
  mut started : Bool
  mut focused : ComponentHandle?
}

///| 创建 TUI。
pub fn TUI::new(terminal : &Terminal) -> TUI {
  {
    terminal,
    root: Container::new(),
    previous_frame: [],
    started: false,
    focused: None,
  }
}

///| 添加根层组件。
pub fn TUI::add_child(self : TUI, component : &Component) -> ComponentHandle {
  self.root.add_child(component)
}

///| 移除根层组件。
pub fn TUI::remove_child(self : TUI, handle : ComponentHandle) -> Unit {
  match self.focused {
    Some(focused) => {
      if focused == handle {
        match self.root.get_child(handle) {
          Some(component) => component.set_focused(false)
          None => ()
        }
        self.focused = None
      }
    }
    None => ()
  }
  self.root.remove_child(handle)
  self.request_render()
}

///| 设置当前聚焦组件。
pub fn TUI::set_focus(self : TUI, handle : ComponentHandle?) -> Unit {
  if self.focused == handle {
    return
  }
  match self.focused {
    Some(previous_handle) =>
      match self.root.get_child(previous_handle) {
        Some(component) => component.set_focused(false)
        None => ()
      }
    None => ()
  }
  self.focused = handle
  match self.focused {
    Some(current_handle) =>
      match self.root.get_child(current_handle) {
        Some(component) => component.set_focused(true)
        None => ()
      }
    None => ()
  }
}

///| 当前是否已经启动。
pub fn TUI::is_started(self : TUI) -> Bool {
  self.started
}

///| 获取最近一次归一化后的帧。
pub fn TUI::frame(self : TUI) -> Array[String] {
  clone_lines(self.previous_frame)
}

///| 启动 TUI 并立即渲染。
pub fn TUI::start(self : TUI) -> Unit {
  if self.started {
    return
  }
  self.started = true
  self.terminal.hide_cursor()
  self.render_now()
}

///| 停止 TUI。
pub fn TUI::stop(self : TUI) -> Unit {
  if !self.started {
    return
  }
  self.started = false
  self.terminal.show_cursor()
}

///| 请求重渲染。
pub fn TUI::request_render(self : TUI) -> Unit {
  if self.started {
    self.render_now()
  }
}

///| 在终端尺寸变化后请求重渲染。
pub fn TUI::handle_resize(self : TUI) -> Unit {
  self.request_render()
}

///| 把输入转发给当前聚焦的组件。
pub fn TUI::handle_input(self : TUI, input : String) -> Bool {
  match self.focused {
    None => false
    Some(handle) =>
      match self.root.get_child(handle) {
        None => false
        Some(component) => {
          let consumed = component.handle_input(input)
          if consumed {
            self.request_render()
          }
          consumed
        }
      }
  }
}

///| 立即执行一次渲染。
pub fn TUI::render_now(self : TUI) -> Unit {
  let size = self.terminal.size()
  let raw_lines = self.root.render(size.width)
  let frame = normalize_frame(raw_lines, size.width, size.height)
  let patch = diff_lines(self.previous_frame, frame)
  self.terminal.present(patch)
  self.previous_frame = clone_lines(frame)
}

fn normalize_frame(lines : Array[String], width : Int, height : Int) -> Array[String] {
  let normalized : Array[String] = []
  let safe_width = if width <= 0 { 1 } else { width }
  let safe_height = if height <= 0 { 0 } else { height }

  for line in lines {
    if normalized.length() >= safe_height {
      break
    }
    normalized.push(fit_to_width(line, safe_width))
  }

  normalized
}

fn clone_lines(lines : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for line in lines {
    result.push(line)
  }
  result
}
