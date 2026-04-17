///| 模糊匹配 / 子序列搜索。
///
/// 算法：query 的每个字符是否都能按顺序在 text 中找到。
/// 得分基于连续匹配长度和 query/text 长度比。

///| 计算模糊匹配得分（0.0-1.0），0.0 表示不匹配。
pub fn fuzzy_score(query : String, text : String) -> Double {
  if query == "" { return 1.0 }
  if text == "" { return 0.0 }
  let q_lower = query.to_lower()
  let t_lower = text.to_lower()
  let mut q_idx = 0
  let mut matches = 0
  let mut consecutive = 0
  let mut max_consecutive = 0
  let mut prev_matched_index = -2
  let mut t_idx = 0
  while t_idx < t_lower.length() && q_idx < q_lower.length() {
    if t_lower[t_idx] == q_lower[q_idx] {
      matches = matches + 1
      if t_idx == prev_matched_index + 1 {
        consecutive = consecutive + 1
      } else {
        consecutive = 1
      }
      if consecutive > max_consecutive {
        max_consecutive = consecutive
      }
      prev_matched_index = t_idx
      q_idx = q_idx + 1
    }
    t_idx = t_idx + 1
  }
  if matches < q_lower.length() { return 0.0 }
  // 得分 = 匹配率 × 连续性加成
  let coverage = matches.to_double() / text.length().to_double()
  let streak_bonus = max_consecutive.to_double() / query.length().to_double()
  coverage * 0.3 + streak_bonus * 0.7
}

///| 按模糊得分过滤并排序候选项。
pub fn fuzzy_filter(query : String, candidates : Array[String]) -> Array[FuzzyMatch] {
  let scored : Array[FuzzyMatch] = []
  for candidate in candidates {
    let score = fuzzy_score(query, candidate)
    if score > 0.0 {
      scored.push({ text: candidate, score })
    }
  }
  // Selection sort by score descending
  let result : Array[FuzzyMatch] = []
  while scored.length() > 0 {
    let mut best = 0
    for i = 1; i < scored.length(); i = i + 1 {
      if scored[i].score > scored[best].score {
        best = i
      }
    }
    result.push(scored[best])
    let remaining : Array[FuzzyMatch] = []
    for i = 0; i < scored.length(); i = i + 1 {
      if i != best { remaining.push(scored[i]) }
    }
    scored.clear()
    for item in remaining { scored.push(item) }
  }
  result
}

///| 模糊匹配结果。
pub(all) struct FuzzyMatch {
  text : String
  score : Double
} derive(Show)

///| 简单前缀匹配过滤。
pub fn prefix_filter(query : String, candidates : Array[String]) -> Array[String] {
  let lower = query.to_lower()
  let result : Array[String] = []
  for candidate in candidates {
    if candidate.to_lower().has_prefix(lower) {
      result.push(candidate)
    }
  }
  result
}
