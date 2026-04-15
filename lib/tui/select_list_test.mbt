test "select list renders selected item and scroll info" {
  let list = SelectList::new(
    [
      { value: "alpha", label: "Alpha", description: Some("first item") },
      { value: "beta", label: "Beta", description: Some("second item") },
      { value: "gamma", label: "Gamma", description: Some("third item") },
    ],
    max_visible=2,
  )
  let rendered = list.render(20)
  assert_eq(rendered.length(), 3)
  assert_eq(rendered[0], "→ Alpha             ")
  assert_eq(rendered[1], "  Beta              ")
  assert_eq(rendered[2], "  (1/3)             ")
}

test "select list moves selection with up and down keys" {
  let list = SelectList::new(
    [
      { value: "alpha", label: "Alpha", description: None },
      { value: "beta", label: "Beta", description: None },
    ],
  )
  assert_true(list.handle_input("\u{1b}[B"))
  match list.get_selected_item() {
    Some(item) => assert_eq(item.value, "beta")
    None => fail("expected selected item")
  }
  assert_true(list.handle_input("\u{1b}[A"))
  match list.get_selected_item() {
    Some(item) => assert_eq(item.value, "alpha")
    None => fail("expected selected item")
  }
}

test "select list wraps when moving past edges" {
  let list = SelectList::new(
    [
      { value: "alpha", label: "Alpha", description: None },
      { value: "beta", label: "Beta", description: None },
    ],
  )
  assert_true(list.handle_input("\u{1b}[A"))
  match list.get_selected_item() {
    Some(item) => assert_eq(item.value, "beta")
    None => fail("expected selected item")
  }
}

test "select list filters by value prefix case-insensitively" {
  let list = SelectList::new(
    [
      { value: "alpha", label: "Alpha", description: None },
      { value: "beta", label: "Beta", description: None },
      { value: "alphabet", label: "Alphabet", description: None },
    ],
  )
  list.set_filter("ALP")
  let rendered = list.render(16)
  assert_eq(rendered.length(), 2)
  assert_eq(rendered[0], "→ Alpha         ")
  assert_eq(rendered[1], "  Alphabet      ")
}

test "select list invokes confirm and cancel callbacks" {
  let list = SelectList::new(
    [
      { value: "alpha", label: "Alpha", description: None },
      { value: "beta", label: "Beta", description: None },
    ],
  )
  let selected : Ref[String?] = Ref::new(None)
  let cancelled : Ref[Bool] = Ref::new(false)
  list.set_select_handler(fn(item) {
    selected.val = Some(item.value)
  })
  list.set_cancel_handler(fn() {
    cancelled.val = true
  })
  assert_true(list.handle_input("\n"))
  assert_eq(selected.val, Some("alpha"))
  assert_true(list.handle_input("\u{1b}"))
  assert_true(cancelled.val)
}
