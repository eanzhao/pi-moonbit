///|
/// Events emitted during LLM response streaming.
///
/// Maps to pi-mono's `AssistantMessageEvent` discriminated union.
/// The stream lifecycle is: Start → (Text|Thinking|ToolCall)* → Done|Error
pub(all) enum AssistantMessageEvent {
  Start(AssistantMessage)
  TextStart(Int)
  TextDelta(Int, String)
  TextEnd(Int, String)
  ThinkingStart(Int)
  ThinkingDelta(Int, String)
  ThinkingEnd(Int, String)
  ToolCallStart(Int, ToolCall)
  ToolCallDelta(Int, String)
  ToolCallEnd(Int, ToolCall)
  Done(StopReason, AssistantMessage)
  Error(StopReason, AssistantMessage)
} derive(Show)

///|
/// Check whether the event signals the end of a stream.
pub fn is_terminal(event : AssistantMessageEvent) -> Bool {
  match event {
    Done(_, _) | Error(_, _) => true
    _ => false
  }
}

///|
/// Extract the final AssistantMessage from a terminal event.
pub fn final_message(event : AssistantMessageEvent) -> AssistantMessage? {
  match event {
    Done(_, msg) | Error(_, msg) => Some(msg)
    _ => None
  }
}
