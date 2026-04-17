///| 组件在容器中的稳定句柄。
pub(all) struct ComponentHandle(Int) derive(Show, Eq)

///| TUI 组件的统一抽象。
/// 组件只需要保证 `render()` 返回的每一行都不超过给定宽度。
pub(open) trait Component {
  render(Self, Int) -> Array[String]
  handle_input(Self, String) -> Bool = _
  invalidate(Self) -> Unit = _
  set_focused(Self, Bool) -> Unit = _
}

impl Component with handle_input(_self, _input) {
  false
}

impl Component with invalidate(_self) {
  ()
}

impl Component with set_focused(_self, _focused) {
  ()
}
