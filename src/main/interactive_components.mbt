///| Interactive Mode 组件渲染器。
///
/// 这里的"组件"是纯函数式渲染器（输入数据 → 输出 ANSI 字符串），
/// 不依赖有状态的 TUI Container 树。适合当前 streaming stdout 模式。

///| 渲染分支摘要消息。
pub fn render_branch_summary_message(theme : Theme, summary : String) -> String {
  theme_colored(theme, "╭── Branch Summary ────────", theme.info) + "\n" +
  theme_colored(theme, summary, theme.secondary) + "\n" +
  theme_colored(theme, "╰──────────────────────────", theme.info)
}

///| 渲染 compaction 摘要消息。
pub fn render_compaction_summary(theme : Theme, summary : String, tokens_saved : Int) -> String {
  theme_colored(theme, "╭── Compacted ─── ", theme.warning) +
  theme_colored(theme, tokens_saved.to_string() + " tokens saved", theme.muted) + "\n" +
  theme_colored(theme, summary, theme.secondary) + "\n" +
  theme_colored(theme, "╰──────────────────", theme.warning)
}

///| 渲染工具调用块。
pub fn render_tool_call(theme : Theme, tool_name : String, args_preview : String) -> String {
  theme_colored(theme, "⟳ " + tool_name, theme.accent_tool) +
  (if args_preview.length() > 0 {
    " " + theme_colored(theme, "(" + args_preview + ")", theme.muted)
  } else { "" })
}

///| 渲染工具结果。
pub fn render_tool_result(theme : Theme, tool_name : String, success : Bool, output : String) -> String {
  let icon = if success { "✓" } else { "✗" }
  let color = if success { theme.success } else { theme.error }
  theme_colored(theme, icon + " " + tool_name, color) + "\n" +
  indent_lines(output, "  ")
}

///| 渲染会话信息面板。
pub fn render_session_panel(
  theme : Theme,
  session_path : String,
  model_id : String,
  thinking_level : String,
  entries : Int
) -> String {
  let title = theme_colored(theme, "── Session ──────────", theme.info)
  let rows = [
    "  " + theme_colored(theme, "path", theme.muted) + "     " + session_path,
    "  " + theme_colored(theme, "model", theme.muted) + "    " + model_id,
    "  " + theme_colored(theme, "thinking", theme.muted) + " " + thinking_level,
    "  " + theme_colored(theme, "entries", theme.muted) + "  " + entries.to_string(),
  ]
  title + "\n" + rows.join("\n")
}

///| 渲染模型选择器。返回的是一个可打印列表。
pub fn render_model_list(
  theme : Theme,
  current_model : String,
  models : Array[ModelEntry]
) -> String {
  let lines : Array[String] = []
  lines.push(theme_colored(theme, "── Models ──────────", theme.info))
  for model in models {
    let marker = if model.id == current_model { "→ " } else { "  " }
    let line = marker + model.id + "  " + theme_colored(theme, "(" + model.provider + ")", theme.muted)
    if model.id == current_model {
      lines.push(theme_colored(theme, line, theme.accent_user))
    } else {
      lines.push(line)
    }
  }
  lines.join("\n")
}

///| 模型条目（用于列表渲染）。
pub(all) struct ModelEntry {
  id : String
  provider : String
  description : String?
} derive(Show)

///| 渲染 thinking level 选择器。
pub fn render_thinking_selector(theme : Theme, current : String) -> String {
  let levels = ["off", "minimal", "low", "medium", "high", "xhigh"]
  let lines : Array[String] = [theme_colored(theme, "── Thinking Level ──", theme.info)]
  for level in levels {
    let marker = if level == current { "→ " } else { "  " }
    let line = marker + level
    if level == current {
      lines.push(theme_colored(theme, line, theme.accent_user))
    } else {
      lines.push(line)
    }
  }
  lines.join("\n")
}

///| 渲染欢迎横幅。
pub fn render_welcome_banner(theme : Theme, model : String, thinking : String) -> String {
  theme_colored(theme, "pi-moonbit", theme.primary) +
  theme_colored(theme, " — interactive mode", theme.muted) + "\n" +
  theme_colored(theme, "model: " + model + "  thinking: " + thinking, theme.muted) + "\n" +
  theme_colored(theme, "Type :help for commands, :quit to exit.", theme.muted)
}

///| 用前缀缩进每一行。
fn indent_lines(text : String, prefix : String) -> String {
  let result : Array[String] = []
  for line in text.split("\n") {
    result.push(prefix + line.to_string())
  }
  result.join("\n")
}
