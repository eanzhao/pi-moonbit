test "loader renders initial frame with message" {
  let loader = Loader::new(message="Working")
  let rendered = loader.render(12)
  assert_eq(rendered.length(), 1)
  assert_eq(rendered[0], " ⠋ Working  ")
}

test "loader advances frame on tick" {
  let loader = Loader::new(message="Run")
  let before = loader.render(8)
  loader.tick()
  let after = loader.render(8)
  assert_eq(before.length(), 1)
  assert_eq(after.length(), 1)
  assert_true(before[0] != after[0])
}
