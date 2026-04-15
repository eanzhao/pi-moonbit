///| LLM 流式响应过程中产生的事件。
///
/// 流的生命周期为：Start → (Text|Thinking|ToolCall)* → Done|Error
/// 其中 Text/Thinking/ToolCall 各自遵循 Start → Delta* → End 的子生命周期，
/// Int 参数为内容块索引，用于标识当前事件对应的 ContentBlock 位置。
pub(all) enum AssistantMessageEvent {
  /// 流开始，携带初始的助手消息骨架
  Start(AssistantMessage)
  /// 文本块开始（参数为内容块索引）
  TextStart(Int)
  /// 文本增量片段
  TextDelta(Int, String)
  /// 文本块结束，携带完整文本
  TextEnd(Int, String)
  /// 思维链开始
  ThinkingStart(Int)
  /// 思维链增量片段
  ThinkingDelta(Int, String)
  /// 思维链结束，携带完整思维内容
  ThinkingEnd(Int, String)
  /// 工具调用开始
  ToolCallStart(Int, ToolCall)
  /// 工具调用参数增量（JSON 片段）
  ToolCallDelta(Int, String)
  /// 工具调用结束，携带完整的 ToolCall
  ToolCallEnd(Int, ToolCall)
  /// 流正常结束
  Done(StopReason, AssistantMessage)
  /// 流因错误结束
  Error(StopReason, AssistantMessage)
} derive(Show)

///| 判断事件是否为终止事件（Done 或 Error）。
pub fn is_terminal(event : AssistantMessageEvent) -> Bool {
  match event {
    Done(_, _) | Error(_, _) => true
    _ => false
  }
}

///| 从终止事件中提取最终的 AssistantMessage。
/// 对于非终止事件返回 None。
pub fn final_message(event : AssistantMessageEvent) -> AssistantMessage? {
  match event {
    Done(_, msg) | Error(_, msg) => Some(msg)
    _ => None
  }
}
