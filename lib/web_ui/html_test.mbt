test "html renderer escapes text and attributes" {
  let node = html_element(
    "div",
    attributes=[html_attr("title", "\"quoted\" & <unsafe>")],
    children=[
      html_text("Hello <world> & others"),
      html_element("img", attributes=[html_attr("src", "https://example.com/x?a=1&b=2")]),
    ],
  )

  assert_eq(
    render_html(node),
    "<div title=\"&quot;quoted&quot; &amp; &lt;unsafe&gt;\">Hello &lt;world&gt; &amp; others<img src=\"https://example.com/x?a=1&amp;b=2\" /></div>",
  )
}

test "render component html delegates to component trait" {
  let component = ThinkingBlockView::new("step by step", is_expanded=true)
  let rendered = render_component_html(component)
  assert_true(rendered.contains("Thinking..."))
  assert_true(rendered.contains("step by step"))
}
