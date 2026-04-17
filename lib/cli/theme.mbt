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
    primary: "\u001b[37m",        // white
    secondary: "\u001b[90m",      // bright black
    muted: "\u001b[2m",           // dim
    accent_user: "\u001b[36m",    // cyan
    accent_assistant: "\u001b[32m", // green
    accent_tool: "\u001b[33m",    // yellow
    accent_system: "\u001b[35m",  // magenta
    success: "\u001b[32m",
    warning: "\u001b[33m",
    error: "\u001b[31m",
    info: "\u001b[34m",
    code_bg: "",
    code_fg: "\u001b[33m",
    reset: "\u001b[0m",
  }
}

///| 浅色主题。
pub fn light_theme() -> Theme {
  {
    name: "light",
    primary: "\u001b[30m",        // black
    secondary: "\u001b[90m",
    muted: "\u001b[2m",
    accent_user: "\u001b[34m",    // blue
    accent_assistant: "\u001b[32m", // green
    accent_tool: "\u001b[33m",    // yellow
    accent_system: "\u001b[35m",
    success: "\u001b[32m",
    warning: "\u001b[33m",
    error: "\u001b[31m",
    info: "\u001b[34m",
    code_bg: "",
    code_fg: "\u001b[36m",
    reset: "\u001b[0m",
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
