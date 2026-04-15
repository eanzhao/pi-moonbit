# 02 - 终端 UI 层：lib/tui

## 这一阶段做了什么？

`lib/tui` 是终端 UI 框架。它让你可以用组件化的方式构建终端界面，并且只重绘发生变化的部分（差分渲染）。

本阶段实现了 **TUI 的核心骨架**：

- 终端抽象 `Terminal`
- 组件 trait `Component`
- 容器组件 `Container`
- 基础文本组件 `Text` 与 `Spacer`
- 布局组件 `Box`
- 单行展示组件 `TruncatedText`
- 单行输入框 `Input`
- 加载组件 `Loader`
- 选择列表 `SelectList`
- 最小按键解析 `KeyEvent`
- 基于行的差分渲染 `ScreenPatch`
- `TUI` 调度器（渲染、焦点、输入转发）

暂时不追求复刻 pi-mono 的全部能力（ANSI 样式、Unicode 宽度、Kitty 键盘协议等），先搭好架构。

## 要解决什么问题？

终端程序的 UI 更新是个麻烦事——你不能每次都清屏重绘（会闪烁），需要只更新变化的部分。同时，终端界面需要组件化：文本、输入框、列表这些元素要能自由组合。

`tui` 包解决两个核心问题：

1. **差分渲染**：算出哪些行变了，只更新那些行
2. **组件系统**：用 trait 定义组件接口，用容器组合组件

## 核心概念

### 组件（Component）

所有 UI 元素都实现 `Component` trait：

```moonbit
pub(open) trait Component {
  render(Self, Int) -> Array[String]  // 给定宽度，返回要渲染的行
  handle_input(Self, String) -> Bool = _  // 处理键盘输入，返回是否消费
  invalidate(Self) -> Unit = _  // 使缓存失效
  set_focused(Self, Bool) -> Unit = _  // 焦点变化通知
}
```

最简单的情况，一个组件只需要实现 `render` —— 给它一个宽度，它返回一行行的文字。`handle_input`、`invalidate` 和 `set_focused` 都有默认实现，简单组件可以不管；像 `Input` 这样需要显示光标的组件则会用 `set_focused` 同步内部状态。

### 容器（Container）

容器把多个组件垂直堆叠起来：

```moonbit
let handle = container.add_child(text_component)
container.remove_child(handle)
```

容器返回一个 `ComponentHandle`（一个整数 ID），用来后续操作这个子组件（删除、聚焦等）。用整数 ID 是因为容器里存的是 trait object，没法直接比较对象相等性。

### 差分渲染（ScreenPatch）

每次渲染时，TUI 会对比新旧两帧，算出一个"补丁"：

```moonbit
enum ScreenPatch {
  Noop
  Full(Array[String])   // 全量更新
  Update(LinePatch)     // 从某一行开始重写，并可清除尾部多余行
}
```

其中 `LinePatch` 会记录 `start_line`、新的行内容，以及需要清掉的尾部行数。策略仍然是：找到第一个发生变化的行，从那里开始重写到末尾。比全屏重绘好，比 pi-mono 原版（精确到行段）简单。

### 终端抽象（Terminal）

`Terminal` trait 把"算出要更新什么"和"怎么更新到屏幕"分开：

```moonbit
pub(open) trait Terminal {
  size(Self) -> TerminalSize
  present(Self, ScreenPatch) -> Unit  // 应用补丁到终端
  clear(Self) -> Unit = _
  hide_cursor(Self) -> Unit = _
  show_cursor(Self) -> Unit = _
}
```

本阶段提供了一个 `MemoryTerminal` 作为测试实现（把内容存在内存里，不真的操作终端）。

### TUI 调度器

`TUI` 是顶层调度器，负责把组件树渲染到终端，并处理输入：

```moonbit
let tui = TUI::new(terminal, root_container)
tui.render()                              // 渲染一帧
tui.set_focus(Some(component_handle))     // 设置焦点组件
tui.handle_input("some key")              // 把输入转发给焦点组件
```

### 文本宽度

终端里的字符不都是一样宽的（中文占 2 列，ANSI 控制码不占列）。本阶段先用简化规则：普通字符算 1 列，`\t` 算 4 列，不处理 ANSI 和 Unicode 宽度。够用了，后续按需加强。

工具函数（`utils.mbt`）提供：`visible_width`（计算可见宽度）、`truncate_to_width`（按宽度截断）、`wrap_lines`（自动换行）、`fit_to_width`（补齐到指定宽度）、`spaces`（生成空格串）。

### 按键事件（KeyEvent）

`keys.mbt` 将原始终端输入解析为稳定的按键事件：

```moonbit
enum KeyEvent {
  Enter | Escape | Backspace | Delete
  Up | Down | Left | Right | Home | End
  TextInput(String)       // 普通可打印字符
  Unsupported(String)     // 无法识别的输入
}
```

`parse_key_event(input)` 覆盖了 Input 组件需要的最小按键集合（方向键、编辑键、Enter/Escape 等）。当前未实现 Kitty 协议，只处理常见的 ANSI 转义序列。

### 内置组件详解

#### Text（纯文本）

最基础的组件，给定宽度和文本内容，返回渲染后的行。长文本会自动换行。

#### Spacer（占位空白）

返回指定行数的空行，用于在组件之间制造间距。

#### Box（带内边距的容器）

给子组件统一加 padding，可选对整行应用背景函数（如 ANSI 颜色转义）：

```moonbit
let box = Box::new(padding_x=2, padding_y=1)
box.add_child(text_component)
box.set_bg_fn(fn(line) { "\x1b[44m" + line + "\x1b[0m" })  // 蓝色背景
```

#### TruncatedText（单行截断文本）

只渲染第一行内容，多余部分按宽度截断。适合标题、状态栏等单行展示场景。

#### Input（单行输入框）

支持文本插入、左右移动、Home/End、Backspace/Delete、Enter 提交、Escape 取消。聚焦时显示 `|` 光标，失焦时隐藏。通过 `set_focused` 同步焦点状态：

```moonbit
let input = Input::new("placeholder")
input.set_submit_handler(fn(value) { println("submitted: " + value) })
input.set_escape_handler(fn() { println("cancelled") })
```

当文本超出可见宽度时，会自动滚动显示窗口，确保光标始终可见。

#### Loader（加载指示器）

通过 Braille 字符动画（⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏）展示加载状态。需要外部定时调用 `tick()` 推进动画帧：

```moonbit
let loader = Loader::new(message="Thinking...")
loader.tick()   // 推进一帧
loader.set_message("Processing...")  // 更新消息
```

#### SelectList（可过滤的选择列表）

支持按 `value` 前缀做大小写不敏感过滤、上下循环导航、Home/End 跳转、Enter 确认、Escape 取消。可配置最大可见行数，超出时自动滚动：

```moonbit
let list = SelectList::new(
  [{ value: "a", label: "Option A", description: "First option" }],
  max_visible=5,
)
list.set_filter("opt")            // 过滤
list.set_select_handler(fn(item) { println("selected: " + item.label) })
list.set_selection_change_handler(fn(item) { println("highlighted: " + item.label) })
```

每个列表项有 `value`（标识符）、`label`（显示文本）、`description`（可选描述）。当终端宽度 > 40 时，描述会显示在标签右侧。

## 文件结构

```
lib/tui/
├── moon.pkg
├── component.mbt      # Component trait 与 ComponentHandle
├── utils.mbt          # 宽度计算、截断、换行、补齐
├── keys.mbt           # 最小按键事件解析
├── diff.mbt           # ScreenPatch 与 diff_lines（差分算法）
├── terminal.mbt       # Terminal trait 与 MemoryTerminal
├── container.mbt      # Container 组件（子组件管理）
├── box.mbt            # 带 padding 的容器
├── text.mbt           # Text 组件（纯文本）
├── truncated_text.mbt # 单行截断文本
├── spacer.mbt         # Spacer 组件（占位空白）
├── input.mbt          # 单行输入框
├── loader.mbt         # 简单加载指示器
├── select_list.mbt    # 可过滤的选择列表
├── tui.mbt            # TUI 主调度器
├── diff_test.mbt      # 差分算法测试
├── components_test.mbt # 组件渲染测试
├── input_test.mbt     # 输入框测试
├── loader_test.mbt    # Loader 测试
├── select_list_test.mbt # SelectList 测试
└── tui_test.mbt       # TUI 调度器测试
```

## 设计决策

### 为什么用 `ComponentHandle` 而不是直接引用组件？

容器里存的是 trait object，没法直接比较对象相等性。所以用一个整数 ID 来标识子组件，用于删除和聚焦操作。

### 为什么差分策略是"从首个变化行重写尾部"？

pi-mono 原版的差分渲染精确到单个行段，实现很复杂。本阶段用更简单的策略，已经避免了全屏重绘，逻辑也简单好验证。

### 为什么用 `pub(open) trait`？

下游包需要定义自己的组件（比如 coding_agent 里的代码编辑器）。`pub(open)` 允许外部包实现这个 trait。

## 和 pi-mono 的差异

| pi-mono 有但我们没做的 | 为什么 |
|------------------------|--------|
| 真实终端实现（进程控制、ANSI 转义） | 先用 MemoryTerminal 验证架构 |
| 精确差分（行段级别） | 先用简化策略，够用 |
| ANSI 样式、emoji、东亚宽字符处理 | 先用简化宽度模型 |
| Kitty 键盘协议 | 先用最小 ANSI 按键解析 |
| 高级组件（Editor、Markdown 等） | 先把当前 CLI 真正需要的最小组件补齐 |
| overlay、IME、图片协议 | 暂不需要 |

## 测试覆盖

本阶段测试聚焦于最核心的能力：

- **diff_test.mbt**：差分算法是否能正确产出 `Noop / Full / Update`（相同帧、空帧、单行变化、多行变化、帧变短需清尾部等场景）
- **components_test.mbt**：基础组件（Text、Spacer、Box、TruncatedText、Loader、SelectList）是否能按宽度正确渲染
- **input_test.mbt**：Input 组件的编辑键（Backspace、Delete、Home、End、左右）、文本插入、提交/取消回调、光标滚动窗口
- **loader_test.mbt**：Loader 动画帧推进和消息更新
- **select_list_test.mbt**：SelectList 的过滤、导航、回调
- **tui_test.mbt**：TUI 是否能把组件树渲染到终端，并把输入转发给聚焦组件

## 后续可以加强的方向

- 更精确的文本宽度计算（ANSI 样式、Unicode 宽度）
- Editor 等高级交互组件
- 更完整的键盘事件规范化
- overlay 和模态层
- 真正的进程终端实现
