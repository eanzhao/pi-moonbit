struct ChildEntry {
  id : ComponentHandle
  component : &Component
}

///| 基础容器组件，按顺序渲染所有子组件。
pub(all) struct Container {
  mut children : Array[ChildEntry]
  mut next_component_id : Int
}

///| 创建空容器。
pub fn Container::new() -> Container {
  { children: [], next_component_id: 0 }
}

///| 添加子组件并返回句柄。
pub fn Container::add_child(self : Container, component : &Component) -> ComponentHandle {
  let handle = ComponentHandle(self.next_component_id)
  self.next_component_id = self.next_component_id + 1
  self.children.push({ id: handle, component })
  handle
}

///| 移除指定句柄对应的子组件。
pub fn Container::remove_child(self : Container, handle : ComponentHandle) -> Unit {
  let retained : Array[ChildEntry] = []
  for child in self.children {
    if child.id != handle {
      retained.push(child)
    }
  }
  self.children = retained
}

///| 清空容器。
pub fn Container::clear(self : Container) -> Unit {
  self.children.clear()
}

///| 子组件数量。
pub fn Container::child_count(self : Container) -> Int {
  self.children.length()
}

///| 根据句柄查找子组件。
pub fn Container::get_child(self : Container, handle : ComponentHandle) -> (&Component)? {
  for child in self.children {
    if child.id == handle {
      return Some(child.component)
    }
  }
  None
}

pub impl Component for Container with render(self, width) {
  let lines : Array[String] = []
  for child in self.children {
    let rendered = child.component.render(width)
    for line in rendered {
      lines.push(line)
    }
  }
  lines
}

pub impl Component for Container with invalidate(self) {
  for child in self.children {
    child.component.invalidate()
  }
}

pub impl Component for Container with set_focused(self, focused) {
  for child in self.children {
    child.component.set_focused(focused)
  }
}
