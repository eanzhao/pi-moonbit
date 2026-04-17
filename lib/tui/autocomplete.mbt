///| 自动补全辅助函数。

///| 自动补全项。
pub(all) struct AutocompleteItem {
  value : String
  display : String
  description : String?
} derive(Show)

///| 自动补全提供者（用户可注册）。
pub(all) struct AutocompleteProvider {
  name : String
  /// 基于输入前缀返回候选项。
  suggest : (String) -> Array[AutocompleteItem]
}

///| 自动补全引擎 — 管理多个 provider。
pub(all) struct AutocompleteEngine {
  mut providers : Array[AutocompleteProvider]
}

pub fn AutocompleteEngine::new() -> AutocompleteEngine {
  { providers: [] }
}

pub fn AutocompleteEngine::register(self : AutocompleteEngine, provider : AutocompleteProvider) -> Unit {
  self.providers.push(provider)
}

///| 收集所有 provider 的候选项。
pub fn AutocompleteEngine::suggest(self : AutocompleteEngine, input : String) -> Array[AutocompleteItem] {
  let all : Array[AutocompleteItem] = []
  for provider in self.providers {
    for item in (provider.suggest)(input) {
      all.push(item)
    }
  }
  all
}

///| 给定输入和光标位置，找到要补全的 token（最后一个 word）。
pub fn extract_completion_token(input : String, cursor : Int) -> String {
  let effective_cursor = if cursor > input.length() { input.length() } else if cursor < 0 { 0 } else { cursor }
  let mut start = effective_cursor
  while start > 0 && !is_token_boundary_code(input[start - 1]) {
    start = start - 1
  }
  input[start:effective_cursor].to_string()
}

fn is_token_boundary(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '/' || ch == '\\'
}

fn is_token_boundary_code(code : UInt16) -> Bool {
  code == 32 || code == 9 || code == 10 || code == 47 || code == 92  // space tab lf / \
}

///| 在输入中替换当前 token 为补全值。
pub fn apply_completion(input : String, cursor : Int, completion : String) -> (String, Int) {
  let effective_cursor = if cursor > input.length() { input.length() } else if cursor < 0 { 0 } else { cursor }
  let mut start = effective_cursor
  while start > 0 && !is_token_boundary_code(input[start - 1]) {
    start = start - 1
  }
  let before = input[:start].to_string()
  let after = input[effective_cursor:].to_string()
  let new_input = before + completion + after
  let new_cursor = start + completion.length()
  (new_input, new_cursor)
}
