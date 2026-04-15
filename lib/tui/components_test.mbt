test "text wraps and pads to target width" {
  let text = Text::new(content="abcdef", padding_x=1, padding_y=1)
  let rendered = text.render(4)
  assert_eq(rendered.length(), 5)
  assert_eq(rendered[0], "    ")
  assert_eq(rendered[1], " ab ")
  assert_eq(rendered[2], " cd ")
  assert_eq(rendered[3], " ef ")
  assert_eq(rendered[4], "    ")
}

test "spacer renders empty lines" {
  let spacer = Spacer::new(line_count=3)
  let rendered = spacer.render(10)
  assert_eq(rendered.length(), 3)
  assert_eq(rendered[0], "")
  assert_eq(rendered[1], "")
  assert_eq(rendered[2], "")
}

test "container keeps child order" {
  let container = Container::new()
  let _ = container.add_child(Text::new(content="first"))
  let _ = container.add_child(Spacer::new(line_count=1))
  let _ = container.add_child(Text::new(content="second"))
  let rendered = container.render(8)
  assert_eq(rendered.length(), 3)
  assert_eq(rendered[0], "first   ")
  assert_eq(rendered[1], "")
  assert_eq(rendered[2], "second  ")
}

test "container removes child by handle" {
  let container = Container::new()
  let first = container.add_child(Text::new(content="first"))
  let _ = container.add_child(Text::new(content="second"))
  container.remove_child(first)
  let rendered = container.render(8)
  assert_eq(rendered.length(), 1)
  assert_eq(rendered[0], "second  ")
}
