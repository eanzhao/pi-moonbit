///| 局部更新 patch。
pub(all) struct LinePatch {
  /// 从哪一行开始重写
  start_line : Int
  /// 需要写入的新行
  lines : Array[String]
  /// 新帧比旧帧更短时，需要清除的尾部行数
  cleared_line_count : Int
} derive(Show, Eq)

///| 一次屏幕更新的抽象表示。
pub(all) enum ScreenPatch {
  Noop
  Full(Array[String])
  Update(LinePatch)
} derive(Show, Eq)

///| 比较前后两帧，生成最小可接受的行级 patch。
/// 当前策略不是极限最优，而是从首个变化行开始重写尾部。
pub fn diff_lines(previous : Array[String], current : Array[String]) -> ScreenPatch {
  if previous.length() == 0 {
    return Full(diff_clone_lines(current))
  }

  let shared_length =
    if previous.length() < current.length() {
      previous.length()
    } else {
      current.length()
    }

  let mut first_changed = -1
  for i = 0; i < shared_length; i = i + 1 {
    if previous[i] != current[i] {
      first_changed = i
      break
    }
  }

  if first_changed == -1 {
    if previous.length() == current.length() {
      return Noop
    }
    first_changed = shared_length
  }

  let lines : Array[String] = []
  for i = first_changed; i < current.length(); i = i + 1 {
    lines.push(current[i])
  }

  let cleared_line_count =
    if previous.length() > current.length() {
      previous.length() - current.length()
    } else {
      0
    }

  Update({
    start_line: first_changed,
    lines,
    cleared_line_count,
  })
}

fn diff_clone_lines(lines : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for line in lines {
    result.push(line)
  }
  result
}
