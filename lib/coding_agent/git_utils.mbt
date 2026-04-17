///| Git 命令封装（纯命令构建，实际执行由 CommandRuntime 完成）。

///| 构建 git status --porcelain 命令。
pub fn git_status_command(cwd : String) -> String {
  "cd " + shell_escape(cwd) + " && git status --porcelain"
}

///| 构建 git diff 命令。
pub fn git_diff_command(cwd : String, staged : Bool) -> String {
  let flag = if staged { " --staged" } else { "" }
  "cd " + shell_escape(cwd) + " && git diff" + flag
}

///| 构建 git log 命令。
pub fn git_log_command(cwd : String, limit : Int) -> String {
  "cd " + shell_escape(cwd) + " && git log --oneline -n " + limit.to_string()
}

///| 构建 git branch --show-current 命令。
pub fn git_current_branch_command(cwd : String) -> String {
  "cd " + shell_escape(cwd) + " && git branch --show-current"
}

///| 构建 git add 命令。
pub fn git_add_command(cwd : String, paths : Array[String]) -> String {
  let escaped = paths.map(shell_escape)
  "cd " + shell_escape(cwd) + " && git add " + escaped.join(" ")
}

///| 构建 git commit 命令（HEREDOC 避免引号问题）。
pub fn git_commit_command(cwd : String, message : String) -> String {
  "cd " + shell_escape(cwd) + " && git commit -m " + shell_escape(message)
}

///| 检查路径是否在 git 仓库内（通过 `git rev-parse --is-inside-work-tree`）。
pub fn git_is_inside_worktree_command(cwd : String) -> String {
  "cd " + shell_escape(cwd) + " && git rev-parse --is-inside-work-tree 2>/dev/null || echo false"
}

///| Shell 转义（单引号包裹并转义内部单引号）。
pub fn shell_escape(s : String) -> String {
  "'" + s.replace(old="'", new="'\\''") + "'"
}

///| 解析 git status --porcelain 输出。
pub(all) struct GitStatusEntry {
  status : String  // 2 字符状态码（如 "M ", "??"）
  path : String
}

pub fn parse_git_status(output : String) -> Array[GitStatusEntry] {
  let entries : Array[GitStatusEntry] = []
  for raw_line in output.split("\n") {
    let line = raw_line.to_string()
    if line.length() < 3 { continue }
    let status = line[:2].to_string()
    let path = line[3:].to_string()
    entries.push({ status, path })
  }
  entries
}

///| Git status 是否有任何变更。
pub fn git_has_changes(entries : Array[GitStatusEntry]) -> Bool {
  entries.length() > 0
}
