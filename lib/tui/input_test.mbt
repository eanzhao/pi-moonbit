test "parse key event recognizes common control keys" {
  assert_true(parse_key_event("\n") == Enter)
  assert_true(parse_key_event("\u{1b}") == Escape)
  assert_true(parse_key_event("\u{7f}") == Backspace)
  assert_true(parse_key_event("\u{1b}[D") == Left)
  assert_true(parse_key_event("\u{1b}[C") == Right)
  assert_true(parse_key_event("\u{1b}[3~") == Delete)
}

test "parse key event recognizes printable text" {
  assert_true(parse_key_event("abc") == TextInput("abc"))
}

test "input inserts characters and moves cursor" {
  let input = Input::new()
  assert_true(input.handle_input("a"))
  assert_true(input.handle_input("b"))
  assert_eq(input.get_value(), "ab")
  assert_eq(input.cursor_offset(), 2)
}

test "input handles backspace and delete" {
  let input = Input::new(value="abcd")
  assert_true(input.handle_input("\u{1b}[D"))
  assert_true(input.handle_input("\u{1b}[D"))
  assert_true(input.handle_input("\u{7f}"))
  assert_eq(input.get_value(), "acd")
  assert_eq(input.cursor_offset(), 1)
  assert_true(input.handle_input("\u{1b}[3~"))
  assert_eq(input.get_value(), "ad")
}

test "input renders cursor when focused" {
  let input = Input::new(value="hello")
  input.set_focused(true)
  let rendered = input.render(8)
  assert_eq(rendered.length(), 1)
  assert_eq(rendered[0], "hello|  ")
}

test "input keeps cursor visible when content exceeds width" {
  let input = Input::new(value="abcdef")
  input.set_focused(true)
  let rendered = input.render(4)
  assert_eq(rendered.length(), 1)
  assert_eq(rendered[0], "def|")
}

test "input submit handler receives current value" {
  let input = Input::new(value="moon")
  let submitted : Ref[String?] = Ref::new(None)
  input.set_submit_handler(fn(value) {
    submitted.val = Some(value)
  })
  assert_true(input.handle_input("\n"))
  assert_eq(submitted.val, Some("moon"))
}

test "tui propagates focus state into input component" {
  let terminal = MemoryTerminal::new(6, 2)
  let input = Input::new(value="ok")
  let tui = TUI::new(terminal)
  let handle = tui.add_child(input)
  tui.set_focus(Some(handle))
  tui.start()

  let snapshot = terminal.snapshot()
  assert_eq(snapshot.length(), 1)
  assert_eq(snapshot[0], "ok|   ")
}
