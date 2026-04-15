struct InputEcho {
  mut lines : Array[String]
}

fn InputEcho::new() -> InputEcho {
  { lines: [""] }
}

pub impl Component for InputEcho with render(self, _width) {
  self.lines
}

pub impl Component for InputEcho with handle_input(self, input) {
  self.lines = [input]
  true
}

test "tui starts with full render" {
  let terminal = MemoryTerminal::new(10, 5)
  let tui = TUI::new(terminal)
  let _ = tui.add_child(Text::new(content="hello"))
  tui.start()

  assert_true(terminal.is_cursor_hidden())
  match terminal.last_screen_patch() {
    Full(lines) => {
      assert_eq(lines.length(), 1)
      assert_eq(lines[0], "hello     ")
    }
    _ => fail("expected full patch")
  }
}

test "tui request_render emits update patch after content changes" {
  let terminal = MemoryTerminal::new(8, 5)
  let text = Text::new(content="hello")
  let tui = TUI::new(terminal)
  let _ = tui.add_child(text)
  tui.start()

  text.set_text("hi")
  tui.request_render()

  match terminal.last_screen_patch() {
    Update(line_patch) => {
      assert_eq(line_patch.start_line, 0)
      assert_eq(line_patch.lines.length(), 1)
      assert_eq(line_patch.lines[0], "hi      ")
    }
    _ => fail("expected update patch")
  }
}

test "tui forwards input to focused component" {
  let terminal = MemoryTerminal::new(6, 4)
  let echo = InputEcho::new()
  let tui = TUI::new(terminal)
  let handle = tui.add_child(echo)
  tui.set_focus(Some(handle))
  tui.start()

  let consumed = tui.handle_input("ok")
  assert_true(consumed)

  let snapshot = terminal.snapshot()
  assert_eq(snapshot.length(), 1)
  assert_eq(snapshot[0], "ok    ")
}

test "tui stop restores cursor visibility" {
  let terminal = MemoryTerminal::new(10, 5)
  let tui = TUI::new(terminal)
  tui.start()
  tui.stop()
  assert_false(terminal.is_cursor_hidden())
}
