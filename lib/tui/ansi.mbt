///| ANSI 转义码常量和终端格式化工具。

///| 重置所有格式。
pub fn ansi_reset() -> String { "\x1b[0m" }

///| 粗体。
pub fn ansi_bold() -> String { "\x1b[1m" }

///| 暗淡。
pub fn ansi_dim() -> String { "\x1b[2m" }

///| 前景色：红色。
pub fn ansi_red() -> String { "\x1b[31m" }

///| 前景色：绿色。
pub fn ansi_green() -> String { "\x1b[32m" }

///| 前景色：黄色。
pub fn ansi_yellow() -> String { "\x1b[33m" }

///| 前景色：蓝色。
pub fn ansi_blue() -> String { "\x1b[34m" }

///| 前景色：品红。
pub fn ansi_magenta() -> String { "\x1b[35m" }

///| 前景色：青色。
pub fn ansi_cyan() -> String { "\x1b[36m" }

///| 前景色：白色。
pub fn ansi_white() -> String { "\x1b[37m" }

///| 前景色：灰色（亮黑）。
pub fn ansi_gray() -> String { "\x1b[90m" }

///| 清除当前行。
pub fn ansi_clear_line() -> String { "\x1b[2K\r" }

///| 光标移到行首。
pub fn ansi_carriage_return() -> String { "\r" }

///| 隐藏光标。
pub fn ansi_hide_cursor_seq() -> String { "\x1b[?25l" }

///| 显示光标。
pub fn ansi_show_cursor_seq() -> String { "\x1b[?25h" }

///| 给文本加颜色。
pub fn ansi_colored(text : String, color : String) -> String {
  color + text + ansi_reset()
}

///| 粗体 + 颜色。
pub fn ansi_bold_colored(text : String, color : String) -> String {
  ansi_bold() + color + text + ansi_reset()
}

///| 格式化用户提示符。
pub fn ansi_user_prompt() -> String {
  ansi_bold() + ansi_cyan() + "you> " + ansi_reset()
}

///| 格式化助手标签。
pub fn ansi_assistant_label() -> String {
  ansi_bold() + ansi_green() + "assistant> " + ansi_reset()
}

///| 格式化工具开始提示。
pub fn ansi_tool_start(tool_name : String) -> String {
  ansi_yellow() + "⟳ " + tool_name + "..." + ansi_reset()
}

///| 格式化工具成功结束。
pub fn ansi_tool_success(tool_name : String) -> String {
  ansi_green() + "✓ " + tool_name + ansi_reset()
}

///| 格式化工具失败结束。
pub fn ansi_tool_error(tool_name : String) -> String {
  ansi_red() + "✗ " + tool_name + " failed" + ansi_reset()
}

///| 格式化错误消息。
pub fn ansi_error(text : String) -> String {
  ansi_red() + text + ansi_reset()
}

///| 格式化暗淡的信息文本。
pub fn ansi_info(text : String) -> String {
  ansi_dim() + text + ansi_reset()
}

///| 用分隔线包围的标题。
pub fn ansi_section_header(text : String) -> String {
  ansi_dim() + "─── " + ansi_reset() + ansi_bold() + text + ansi_reset() + ansi_dim() + " ───" + ansi_reset()
}
