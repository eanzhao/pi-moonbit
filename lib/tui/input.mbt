///| 单行输入框组件。
/// 当前版本支持：
/// - 文本插入
/// - 左右移动
/// - Home / End
/// - Backspace / Delete
/// - Enter 提交
/// - Escape 回调
pub(all) struct Input {
  mut value : String
  mut cursor : Int
  mut focused : Bool
  mut on_submit : ((String) -> Unit)?
  mut on_escape : (() -> Unit)?
}

///| 创建输入框。
pub fn Input::new(value? : String = "") -> Input {
  let initial_value = value
  {
    value: initial_value,
    cursor: initial_value.length(),
    focused: false,
    on_submit: None,
    on_escape: None,
  }
}

///| 获取当前文本。
pub fn Input::get_value(self : Input) -> String {
  self.value
}

///| 用新值覆盖输入框内容，并把光标移动到末尾。
pub fn Input::set_value(self : Input, value : String) -> Unit {
  self.value = value
  self.cursor = value.length()
}

///| 清空输入框。
pub fn Input::clear(self : Input) -> Unit {
  self.value = ""
  self.cursor = 0
}

///| 当前光标所在的 UTF-16 偏移。
pub fn Input::cursor_offset(self : Input) -> Int {
  self.cursor
}

///| 将光标移动到末尾。
pub fn Input::move_cursor_to_end(self : Input) -> Unit {
  self.cursor = self.value.length()
}

///| 设置提交回调。
pub fn Input::set_submit_handler(self : Input, handler : (String) -> Unit) -> Unit {
  self.on_submit = Some(handler)
}

///| 设置取消回调。
pub fn Input::set_escape_handler(self : Input, handler : () -> Unit) -> Unit {
  self.on_escape = Some(handler)
}

pub impl Component for Input with render(self, width) {
  if width <= 0 {
    return []
  }
  let line =
    if self.focused {
      input_render_focused_line(self, width)
    } else {
      input_render_unfocused_line(self, width)
    }
  [fit_to_width(line, width)]
}

pub impl Component for Input with handle_input(self, input) {
  match parse_key_event(input) {
    Enter => {
      match self.on_submit {
        Some(handler) => handler(self.value)
        None => ()
      }
      true
    }
    Escape => {
      match self.on_escape {
        Some(handler) => handler()
        None => ()
      }
      true
    }
    Backspace => {
      if self.cursor <= 0 {
        return true
      }
      let start = input_previous_char_start(self.value, self.cursor)
      self.value = input_slice(self.value, 0, start) + input_slice(self.value, self.cursor, self.value.length())
      self.cursor = start
      true
    }
    Delete => {
      if self.cursor >= self.value.length() {
        return true
      }
      let end = input_next_char_end(self.value, self.cursor)
      self.value = input_slice(self.value, 0, self.cursor) + input_slice(self.value, end, self.value.length())
      true
    }
    Left => {
      self.cursor = input_previous_char_start(self.value, self.cursor)
      true
    }
    Right => {
      self.cursor = input_next_char_end(self.value, self.cursor)
      true
    }
    Home => {
      self.cursor = 0
      true
    }
    End => {
      self.cursor = self.value.length()
      true
    }
    TextInput(text) => {
      self.value =
        input_slice(self.value, 0, self.cursor) + text +
        input_slice(self.value, self.cursor, self.value.length())
      self.cursor = self.cursor + text.length()
      true
    }
    Unsupported(_) => false
  }
}

pub impl Component for Input with set_focused(self, focused) {
  self.focused = focused
}

fn input_render_focused_line(input : Input, width : Int) -> String {
  let marker = "|"
  let visible_capacity = input_max_int(0, width - marker.length())
  let start = input_window_start(input.value.length(), input.cursor, visible_capacity)
  let before = input_slice(input.value, start, input.cursor)
  let remaining_capacity = input_max_int(0, visible_capacity - before.length())
  let after_end = input_min_int(input.value.length(), input.cursor + remaining_capacity)
  let after = input_slice(input.value, input.cursor, after_end)
  before + marker + after
}

fn input_render_unfocused_line(input : Input, width : Int) -> String {
  let start = input_window_start(input.value.length(), input.cursor, width)
  let end = input_min_int(input.value.length(), start + width)
  input_slice(input.value, start, end)
}

fn input_window_start(value_length : Int, cursor : Int, capacity : Int) -> Int {
  if capacity <= 0 || value_length <= capacity || cursor <= capacity {
    0
  } else if cursor >= value_length {
    input_max_int(0, value_length - capacity)
  } else {
    let candidate = cursor - capacity + 1
    if candidate + capacity > value_length {
      input_max_int(0, value_length - capacity)
    } else {
      candidate
    }
  }
}

fn input_previous_char_start(text : String, cursor : Int) -> Int {
  match text.offset_of_nth_char(-1, end_offset=cursor) {
    Some(offset) => offset
    None => 0
  }
}

fn input_next_char_end(text : String, cursor : Int) -> Int {
  match text.offset_of_nth_char(1, start_offset=cursor) {
    Some(offset) => offset
    None => text.length()
  }
}

fn input_slice(text : String, start : Int, end : Int) -> String {
  text[start:end].to_string()
}

fn input_min_int(a : Int, b : Int) -> Int {
  if a < b { a } else { b }
}

fn input_max_int(a : Int, b : Int) -> Int {
  if a > b { a } else { b }
}
