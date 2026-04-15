# 02 - 终端 UI 层：lib/tui

## 这一阶段做了什么？

`lib/tui` 是终端 UI 框架。它让你可以用组件化的方式构建终端界面，并且只重绘发生变化的部分（差分渲染）。

本阶段实现了 **TUI 的核心骨架**：

- 终端抽象 `Terminal`
- 组件 trait `Component`
- 容器组件 `Container`
- 基础文本组件 `Text` 与 `Spacer`
- 单行输入框 `Input`
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
}
```

最简单的情况，一个组件只需要实现 `render` —— 给它一个宽度，它返回一行行的文字。`handle_input` 和 `invalidate` 有默认实现，简单组件可以不管。

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
  Full(Array[String])           // 全量更新
  Update(Int, Array[String])    // 从第 N 行开始更新
  Noop                          // 没有变化，什么都不做
}
```

策略：找到第一个发生变化的行，从那里开始重写到末尾。比全屏重绘好，比 pi-mono 原版（精确到行段）简单。

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
├── text.mbt           # Text 组件（纯文本）
├── spacer.mbt         # Spacer 组件（占位空白）
├── input.mbt          # 单行输入框
├── tui.mbt            # TUI 主调度器
├── diff_test.mbt      # 差分算法测试
├── components_test.mbt # 组件渲染测试
├── input_test.mbt     # 输入框测试
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
| Kitty 键盘协议 | 先用原始字符串转发 |
| 高级组件（Editor、Markdown、SelectList 等） | 先有基础组件 |
| overlay、IME、图片协议 | 暂不需要 |

## 后续可以加强的方向

- 更精确的文本宽度计算（ANSI 样式、Unicode 宽度）
- Editor 等高级交互组件
- 键盘事件规范化
- overlay 和模态层
- 真正的进程终端实现
