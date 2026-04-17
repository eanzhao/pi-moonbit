///| 可选列表项。
pub(all) struct SelectItem {
  value : String
  label : String
  description : String?
} derive(Show, Eq)

///| 列表选择组件。
/// 支持过滤、上下导航、确认和取消。
pub(all) struct SelectList {
  mut items : Array[SelectItem]
  mut filtered_items : Array[SelectItem]
  mut selected_index : Int
  max_visible : Int
  mut on_select : ((SelectItem) -> Unit)?
  mut on_cancel : (() -> Unit)?
  mut on_selection_change : ((SelectItem) -> Unit)?
}

///| 创建选择列表。
pub fn SelectList::new(items : Array[SelectItem], max_visible? : Int = 5) -> SelectList {
  let visible_count = select_list_max_int(1, max_visible)
  {
    items,
    filtered_items: select_list_clone_items(items),
    selected_index: 0,
    max_visible: visible_count,
    on_select: None,
    on_cancel: None,
    on_selection_change: None,
  }
}

///| 更新过滤条件，按 `value` 前缀做大小写不敏感匹配。
pub fn SelectList::set_filter(self : SelectList, filter : String) -> Unit {
  let normalized_filter = filter.to_lower()
  let filtered : Array[SelectItem] = []
  for item in self.items {
    if normalized_filter == "" || item.value.to_lower().has_prefix(normalized_filter) {
      filtered.push(item)
    }
  }
  self.filtered_items = filtered
  self.selected_index = 0
  select_list_notify_selection_change(self)
}

///| 设置当前选中索引。
pub fn SelectList::set_selected_index(self : SelectList, index : Int) -> Unit {
  if self.filtered_items.length() == 0 {
    self.selected_index = 0
    return
  }
  self.selected_index = select_list_clamp(index, 0, self.filtered_items.length() - 1)
  select_list_notify_selection_change(self)
}

///| 设置确认回调。
pub fn SelectList::set_select_handler(self : SelectList, handler : (SelectItem) -> Unit) -> Unit {
  self.on_select = Some(handler)
}

///| 设置取消回调。
pub fn SelectList::set_cancel_handler(self : SelectList, handler : () -> Unit) -> Unit {
  self.on_cancel = Some(handler)
}

///| 设置选择变化回调。
pub fn SelectList::set_selection_change_handler(
  self : SelectList,
  handler : (SelectItem) -> Unit
) -> Unit {
  self.on_selection_change = Some(handler)
}

///| 获取当前选中的项目。
pub fn SelectList::get_selected_item(self : SelectList) -> SelectItem? {
  if self.filtered_items.length() == 0 {
    None
  } else {
    Some(self.filtered_items[self.selected_index])
  }
}

pub impl Component for SelectList with render(self, width) {
  let result : Array[String] = []
  if self.filtered_items.length() == 0 {
    result.push(fit_to_width("  No matching items", width))
    return result
  }

  let start_index = select_list_visible_start(
    self.selected_index,
    self.filtered_items.length(),
    self.max_visible,
  )
  let end_index = select_list_min_int(start_index + self.max_visible, self.filtered_items.length())

  for i = start_index; i < end_index; i = i + 1 {
    let item = self.filtered_items[i]
    result.push(
      select_list_render_item(
        item,
        i == self.selected_index,
        width,
      ),
    )
  }

  if start_index > 0 || end_index < self.filtered_items.length() {
    let info =
      "  (" + (self.selected_index + 1).to_string() + "/" + self.filtered_items.length().to_string() + ")"
    result.push(fit_to_width(info, width))
  }

  result
}

pub impl Component for SelectList with handle_input(self, input) {
  if self.filtered_items.length() == 0 {
    match parse_key_event(input) {
      Escape => {
        match self.on_cancel {
          Some(handler) => handler()
          None => ()
        }
        return true
      }
      _ => return false
    }
  }

  match parse_key_event(input) {
    Up => {
      if self.selected_index == 0 {
        self.selected_index = self.filtered_items.length() - 1
      } else {
        self.selected_index = self.selected_index - 1
      }
      select_list_notify_selection_change(self)
      true
    }
    Down => {
      if self.selected_index == self.filtered_items.length() - 1 {
        self.selected_index = 0
      } else {
        self.selected_index = self.selected_index + 1
      }
      select_list_notify_selection_change(self)
      true
    }
    Home => {
      self.selected_index = 0
      select_list_notify_selection_change(self)
      true
    }
    End => {
      self.selected_index = self.filtered_items.length() - 1
      select_list_notify_selection_change(self)
      true
    }
    Enter => {
      match self.on_select {
        Some(handler) => handler(self.filtered_items[self.selected_index])
        None => ()
      }
      true
    }
    Escape => {
      match self.on_cancel {
        Some(handler) => handler()
        None => ()
      }
      true
    }
    _ => false
  }
}

fn select_list_render_item(item : SelectItem, selected : Bool, width : Int) -> String {
  let prefix = if selected { "→ " } else { "  " }
  let prefix_width = visible_width(prefix)
  let primary = select_list_display_text(item)
  let available = select_list_max_int(1, width - prefix_width)

  match item.description {
    Some(description) if width > 40 => {
      let normalized_description = select_list_normalize_single_line(description)
      let primary_width = select_list_max_int(8, select_list_min_int(24, available / 2))
      let rendered_primary = truncate_to_width(primary, primary_width)
      let spacing_width = select_list_max_int(1, primary_width - visible_width(rendered_primary) + 2)
      let rendered_description =
        truncate_to_width(
          normalized_description,
          select_list_max_int(1, available - visible_width(rendered_primary) - spacing_width),
        )
      fit_to_width(
        prefix + rendered_primary + spaces(spacing_width) + rendered_description,
        width,
      )
    }
    _ => fit_to_width(prefix + truncate_to_width(primary, available), width)
  }
}

fn select_list_display_text(item : SelectItem) -> String {
  if item.label == "" { item.value } else { item.label }
}

fn select_list_normalize_single_line(text : String) -> String {
  text.replace_all(old="\n", new=" ").replace_all(old="\r", new=" ").trim().to_string()
}

fn select_list_visible_start(selected_index : Int, total : Int, max_visible : Int) -> Int {
  let start = selected_index - max_visible / 2
  let max_start = select_list_max_int(0, total - max_visible)
  select_list_clamp(start, 0, max_start)
}

fn select_list_notify_selection_change(list : SelectList) -> Unit {
  if list.filtered_items.length() == 0 {
    return
  }
  match list.on_selection_change {
    Some(handler) => handler(list.filtered_items[list.selected_index])
    None => ()
  }
}

fn select_list_clone_items(items : Array[SelectItem]) -> Array[SelectItem] {
  let cloned : Array[SelectItem] = []
  for item in items {
    cloned.push(item)
  }
  cloned
}

fn select_list_clamp(value : Int, min_value : Int, max_value : Int) -> Int {
  if value < min_value {
    min_value
  } else if value > max_value {
    max_value
  } else {
    value
  }
}

fn select_list_min_int(a : Int, b : Int) -> Int {
  if a < b { a } else { b }
}

fn select_list_max_int(a : Int, b : Int) -> Int {
  if a > b { a } else { b }
}
