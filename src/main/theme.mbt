///| 主题系统 — Interactive Mode 的配色方案。

pub(all) struct Theme {
  name : String
  // Foreground colors
  primary : String       // 主要文本
  secondary : String     // 次要文本
  muted : String         // 暗淡文本
  // Accent colors
  accent_user : String
  accent_assistant : String
  accent_tool : String
  accent_system : String
  // Status colors
  success : String
  warning : String
  error : String
  info : String
  // Code
  code_bg : String       // 背景（不用时置空）
  code_fg : String
  // Reset
  reset : String
} derive(Show)

///| 深色主题（默认）。
pub fn dark_theme() -> Theme {
  {
    name: "dark",
    primary: "\x1b[37m",        // white
    secondary: "\x1b[90m",      // bright black
    muted: "\x1b[2m",           // dim
    accent_user: "\x1b[36m",    // cyan
    accent_assistant: "\x1b[32m", // green
    accent_tool: "\x1b[33m",    // yellow
    accent_system: "\x1b[35m",  // magenta
    success: "\x1b[32m",
    warning: "\x1b[33m",
    error: "\x1b[31m",
    info: "\x1b[34m",
    code_bg: "",
    code_fg: "\x1b[33m",
    reset: "\x1b[0m",
  }
}

///| 浅色主题。
pub fn light_theme() -> Theme {
  {
    name: "light",
    primary: "\x1b[30m",        // black
    secondary: "\x1b[90m",
    muted: "\x1b[2m",
    accent_user: "\x1b[34m",    // blue
    accent_assistant: "\x1b[32m", // green
    accent_tool: "\x1b[33m",    // yellow
    accent_system: "\x1b[35m",
    success: "\x1b[32m",
    warning: "\x1b[33m",
    error: "\x1b[31m",
    info: "\x1b[34m",
    code_bg: "",
    code_fg: "\x1b[36m",
    reset: "\x1b[0m",
  }
}

///| 按名称获取主题。
pub fn get_theme(name : String) -> Theme {
  match name {
    "light" => light_theme()
    _ => dark_theme()
  }
}

///| 用主题包装文本。
pub fn theme_colored(theme : Theme, text : String, color : String) -> String {
  color + text + theme.reset
}
