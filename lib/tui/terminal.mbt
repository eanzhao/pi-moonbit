///| 终端当前的可用尺寸。
pub(all) struct TerminalSize {
  mut width : Int
  mut height : Int
} derive(Debug, Eq)

///| 终端输出抽象。
/// 当前阶段只要求终端能够应用 `ScreenPatch`。
pub(open) trait Terminal {
  size(Self) -> TerminalSize
  present(Self, ScreenPatch) -> Unit
  clear(Self) -> Unit = _
  hide_cursor(Self) -> Unit = _
  show_cursor(Self) -> Unit = _
  set_title(Self, String) -> Unit = _
}

impl Terminal with clear(_self) {
  ()
}

impl Terminal with hide_cursor(_self) {
  ()
}

impl Terminal with show_cursor(_self) {
  ()
}

impl Terminal with set_title(_self, _title) {
  ()
}

///| 一个仅保存在内存里的终端实现，主要用于测试和演示。
pub(all) struct MemoryTerminal {
  mut size_value : TerminalSize
  mut lines : Array[String]
  mut last_patch : ScreenPatch
  mut title : String
  mut cursor_hidden : Bool
}

///| 创建内存终端。
pub fn MemoryTerminal::new(width : Int, height : Int) -> MemoryTerminal {
  {
    size_value: {
      width: normalize_width(width),
      height: normalize_height(height),
    },
    lines: [],
    last_patch: Noop,
    title: "",
    cursor_hidden: false,
  }
}

///| 调整终端尺寸。
pub fn MemoryTerminal::resize(self : MemoryTerminal, width : Int, height : Int) -> Unit {
  self.size_value.width = normalize_width(width)
  self.size_value.height = normalize_height(height)
}

///| 获取当前视口快照。
pub fn MemoryTerminal::snapshot(self : MemoryTerminal) -> Array[String] {
  terminal_clone_lines(self.lines)
}

///| 获取最近一次 patch。
pub fn MemoryTerminal::last_screen_patch(self : MemoryTerminal) -> ScreenPatch {
  terminal_clone_patch(self.last_patch)
}

///| 当前硬件光标是否被隐藏。
pub fn MemoryTerminal::is_cursor_hidden(self : MemoryTerminal) -> Bool {
  self.cursor_hidden
}

///| 当前终端标题。
pub fn MemoryTerminal::current_title(self : MemoryTerminal) -> String {
  self.title
}

pub impl Terminal for MemoryTerminal with size(self) {
  self.size_value
}

pub impl Terminal for MemoryTerminal with present(self, patch) {
  match patch {
    Noop => self.last_patch = Noop
    Full(lines) => {
      self.last_patch = Full(terminal_clone_lines(lines))
      self.lines = terminal_clone_lines(lines)
    }
    Update(line_patch) => {
      self.last_patch = Update({
        start_line: line_patch.start_line,
        lines: terminal_clone_lines(line_patch.lines),
        cleared_line_count: line_patch.cleared_line_count,
      })
      memory_terminal_apply_update(self, line_patch)
    }
  }
}

pub impl Terminal for MemoryTerminal with clear(self) {
  self.lines.clear()
}

pub impl Terminal for MemoryTerminal with hide_cursor(self) {
  self.cursor_hidden = true
}

pub impl Terminal for MemoryTerminal with show_cursor(self) {
  self.cursor_hidden = false
}

pub impl Terminal for MemoryTerminal with set_title(self, title) {
  self.title = title
}

fn memory_terminal_apply_update(term : MemoryTerminal, patch : LinePatch) -> Unit {
  for i = 0; i < patch.lines.length(); i = i + 1 {
    let index = patch.start_line + i
    while term.lines.length() < index {
      term.lines.push("")
    }
    if index < term.lines.length() {
      term.lines[index] = patch.lines[i]
    } else {
      term.lines.push(patch.lines[i])
    }
  }

  if patch.cleared_line_count > 0 {
    let desired_length = patch.start_line + patch.lines.length()
    let retained : Array[String] = []
    for i = 0; i < desired_length && i < term.lines.length(); i = i + 1 {
      retained.push(term.lines[i])
    }
    term.lines = retained
  }
}

fn terminal_clone_lines(lines : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for line in lines {
    result.push(line)
  }
  result
}

fn terminal_clone_patch(patch : ScreenPatch) -> ScreenPatch {
  match patch {
    Noop => Noop
    Full(lines) => Full(terminal_clone_lines(lines))
    Update(line_patch) => {
      Update({
        start_line: line_patch.start_line,
        lines: terminal_clone_lines(line_patch.lines),
        cleared_line_count: line_patch.cleared_line_count,
      })
    }
  }
}

fn normalize_width(width : Int) -> Int {
  if width <= 0 { 1 } else { width }
}

fn normalize_height(height : Int) -> Int {
  if height <= 0 { 0 } else { height }
}
