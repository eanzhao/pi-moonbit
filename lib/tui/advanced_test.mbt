test "fuzzy_score matches subsequence" {
  assert_true(fuzzy_score("fb", "foo-bar") > 0.0)
  assert_true(fuzzy_score("xyz", "foo") == 0.0)
  assert_eq(fuzzy_score("", "anything"), 1.0)
}

test "fuzzy_score ranks consecutive matches higher" {
  let a = fuzzy_score("fo", "foo")       // consecutive
  let b = fuzzy_score("fo", "far-other") // gap between
  assert_true(a > b)
}

test "fuzzy_filter sorts by score" {
  let results = fuzzy_filter("cm", ["commit", "clm", "other"])
  assert_true(results.length() >= 2)
  // First should have higher score
  if results.length() >= 2 {
    assert_true(results[0].score >= results[1].score)
  }
}

test "prefix_filter matches prefixes" {
  let result = prefix_filter("co", ["commit", "config", "push", "Collect"])
  assert_true(result.contains("commit"))
  assert_true(result.contains("config"))
  assert_true(result.contains("Collect"))
  assert_false(result.contains("push"))
}

test "extract_completion_token returns last word" {
  assert_eq(extract_completion_token("git co", 6), "co")
  assert_eq(extract_completion_token("git commit -m", 13), "-m")
  assert_eq(extract_completion_token("", 0), "")
}

test "apply_completion replaces token" {
  let (result, cursor) = apply_completion("git co", 6, "commit")
  assert_eq(result, "git commit")
  assert_eq(cursor, 10)
}

test "undo stack push and undo" {
  let stack : UndoStack[String] = UndoStack::new()
  stack.push("v1")
  stack.push("v2")
  stack.push("v3")
  assert_eq(stack.current(), Some("v3"))
  assert_eq(stack.undo(), Some("v2"))
  assert_eq(stack.undo(), Some("v1"))
  assert_eq(stack.undo(), None)
  assert_false(stack.can_undo())
}

test "undo stack redo after undo" {
  let stack : UndoStack[Int] = UndoStack::new()
  stack.push(1)
  stack.push(2)
  stack.push(3)
  ignore(stack.undo())
  ignore(stack.undo())
  assert_eq(stack.current(), Some(1))
  assert_eq(stack.redo(), Some(2))
  assert_eq(stack.redo(), Some(3))
  assert_false(stack.can_redo())
}

test "undo stack drops redo history on new push" {
  let stack : UndoStack[Int] = UndoStack::new()
  stack.push(1)
  stack.push(2)
  stack.push(3)
  ignore(stack.undo())  // now at 2
  stack.push(99)        // should drop "3" from redo
  assert_false(stack.can_redo())
  assert_eq(stack.current(), Some(99))
}

test "autocomplete engine aggregates providers" {
  let engine = AutocompleteEngine::new()
  engine.register({
    name: "commands",
    suggest: fn(_input) {
      [{ value: ":help", display: ":help", description: None }]
    },
  })
  engine.register({
    name: "files",
    suggest: fn(_input) {
      [{ value: "foo.mbt", display: "foo.mbt", description: None }]
    },
  })
  let items = engine.suggest("")
  assert_eq(items.length(), 2)
}
