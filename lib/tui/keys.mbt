///| TUI 层规范化后的按键事件。
pub(all) enum KeyEvent {
  Enter
  Escape
  Backspace
  Delete
  Up
  Down
  Left
  Right
  Home
  End
  TextInput(String)
  Unsupported(String)
} derive(Debug, Eq)

///| 将原始终端输入解析为较稳定的按键事件。
/// 当前只覆盖 `Input` 组件需要的最小集合。
pub fn parse_key_event(input : String) -> KeyEvent {
  match input {
    "\n" | "\r" | "\r\n" => Enter
    "\u{1b}" | "\u{03}" => Escape
    "\u{7f}" | "\b" => Backspace
    "\u{1b}[3~" => Delete
    "\u{1b}[A" => Up
    "\u{1b}[B" => Down
    "\u{1b}[D" => Left
    "\u{1b}[C" => Right
    "\u{1b}[H" | "\u{01}" => Home
    "\u{1b}[F" | "\u{05}" => End
    _ =>
      if is_printable_input(input) {
        TextInput(input)
      } else {
        Unsupported(input)
      }
  }
}

fn is_printable_input(input : String) -> Bool {
  if input == "" {
    return false
  }
  for ch in input.iter() {
    let code = ch.to_int()
    if code < 32 || code == 127 {
      return false
    }
  }
  true
}
