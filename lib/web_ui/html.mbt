pub(all) enum HtmlNode {
  Element(HtmlElement)
  Text(String)
  Fragment(Array[HtmlNode])
}

pub(all) struct HtmlElement {
  tag : String
  attributes : Array[HtmlAttribute]
  children : Array[HtmlNode]
}

pub(all) struct HtmlAttribute {
  name : String
  value : String?
}

pub(open) trait WebComponent {
  render(Self) -> HtmlNode
}

pub fn html_element(
  tag : String,
  attributes? : Array[HtmlAttribute] = [],
  children? : Array[HtmlNode] = []
) -> HtmlNode {
  Element({ tag, attributes: attributes.copy(), children: children.copy() })
}

pub fn html_text(text : String) -> HtmlNode {
  Text(text)
}

pub fn html_fragment(children : Array[HtmlNode]) -> HtmlNode {
  Fragment(children.copy())
}

pub fn html_attr(name : String, value : String) -> HtmlAttribute {
  { name, value: Some(value) }
}

pub fn html_bool_attr(name : String) -> HtmlAttribute {
  { name, value: None }
}

pub fn html_class(value : String) -> HtmlAttribute {
  html_attr("class", value)
}

pub fn html_data_attr(name : String, value : String) -> HtmlAttribute {
  html_attr("data-" + name, value)
}

pub fn[T : WebComponent] render_component_html(component : T) -> String {
  render_html(component.render())
}

pub fn render_html(node : HtmlNode) -> String {
  match node {
    Text(text) => escape_html_text(text)
    Fragment(children) => render_html_children(children)
    Element(element) => render_html_element(element)
  }
}

pub fn join_html_classes(classes : Array[String]) -> String {
  let filtered : Array[String] = []
  for class_name in classes {
    let normalized = class_name.trim().to_string()
    if normalized.length() > 0 {
      filtered.push(normalized)
    }
  }
  filtered.join(" ")
}

fn render_html_element(element : HtmlElement) -> String {
  let attributes = render_html_attributes(element.attributes)
  let open_tag =
    if attributes.length() > 0 {
      "<" + element.tag + " " + attributes + ">"
    } else {
      "<" + element.tag + ">"
    }
  if html_void_tag(element.tag) {
    if attributes.length() > 0 {
      "<" + element.tag + " " + attributes + " />"
    } else {
      "<" + element.tag + " />"
    }
  } else {
    open_tag + render_html_children(element.children) + "</" + element.tag + ">"
  }
}

fn render_html_children(children : Array[HtmlNode]) -> String {
  let rendered : Array[String] = []
  for child in children {
    rendered.push(render_html(child))
  }
  rendered.join("")
}

fn render_html_attributes(attributes : Array[HtmlAttribute]) -> String {
  let rendered : Array[String] = []
  for attribute in attributes {
    match attribute.value {
      Some(value) =>
        rendered.push(attribute.name + "=\"" + escape_html_attribute(value) + "\"")
      None => rendered.push(attribute.name)
    }
  }
  rendered.join(" ")
}

fn escape_html_text(text : String) -> String {
  text
    .replace_all(old="&", new="&amp;")
    .replace_all(old="<", new="&lt;")
    .replace_all(old=">", new="&gt;")
}

fn escape_html_attribute(text : String) -> String {
  escape_html_text(text)
    .replace_all(old="\"", new="&quot;")
    .replace_all(old="'", new="&#39;")
}

fn html_void_tag(tag : String) -> Bool {
  tag == "img" ||
  tag == "br" ||
  tag == "hr" ||
  tag == "input" ||
  tag == "meta" ||
  tag == "link"
}
