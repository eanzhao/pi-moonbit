test "headers render with expected ANSI codes" {
  assert_eq(render_markdown("# Title", 80), ansi_bold() + ansi_cyan() + "Title" + ansi_reset())
  assert_eq(render_markdown("## Title", 80), ansi_bold() + ansi_blue() + "Title" + ansi_reset())
  assert_eq(render_markdown("### Title", 80), ansi_bold() + "Title" + ansi_reset())
}

test "code blocks render with dim separators and indented content" {
  let input = "```moonbit\nlet x = 1\n```\n"
  let expected = [
    ansi_dim() + "───" + ansi_reset(),
    ansi_dim() + "  let x = 1" + ansi_reset(),
    ansi_dim() + "───" + ansi_reset(),
    "",
  ].join("\n")
  assert_eq(render_markdown(input, 80), expected)
}

test "inline code renders yellow" {
  assert_eq(
    render_markdown_inline("use `moon test`"),
    "use " + ansi_yellow() + "moon test" + ansi_reset(),
  )
}

test "bold renders bold" {
  assert_eq(
    render_markdown_inline("say **hello**"),
    "say " + ansi_bold() + "hello" + ansi_reset(),
  )
}

test "lists get bullet markers" {
  assert_eq(render_markdown("- item", 80), "  • item")
  assert_eq(render_markdown("* item", 80), "  • item")
  assert_eq(render_markdown("1. item", 80), "  1. item")
}

test "blockquotes get dim prefix" {
  assert_eq(
    render_markdown("> quoted", 80),
    ansi_dim() + "│ quoted" + ansi_reset(),
  )
}

test "mixed content renders header paragraph and code block" {
  let input = "# Title\nHello **world** and `moon`.\n```moonbit\nlet x = 1\n```"
  let expected = [
    ansi_bold() + ansi_cyan() + "Title" + ansi_reset(),
    "Hello " + ansi_bold() + "world" + ansi_reset() + " and " +
    ansi_yellow() + "moon" + ansi_reset() + ".",
    ansi_dim() + "───" + ansi_reset(),
    ansi_dim() + "  let x = 1" + ansi_reset(),
    ansi_dim() + "───" + ansi_reset(),
  ].join("\n")
  assert_eq(render_markdown(input, 80), expected)
}
