///|
pub(all) enum CacheRetention {
  None
  Short
  Long
} derive(Show, Eq)

///|
pub(all) enum ThinkingLevel {
  Minimal
  Low
  Medium
  High
  XHigh
} derive(Show, Eq)

///|
pub(all) enum ThinkingMode {
  Disabled
  Enabled
  Adaptive
} derive(Show, Eq)

///|
pub(all) struct Tool {
  name : String
  description : String
  parameters : Json
} derive(Show)

///|
pub(all) struct StreamOptions {
  temperature : Double?
  max_tokens : Int?
  top_p : Double?
  api_key : String?
  cache_retention : CacheRetention?
  retry_count : Int?
  retry_delay_ms : Int?
  thinking_mode : ThinkingMode?
  thinking_budget_tokens : Int?
  reasoning : ThinkingLevel?
} derive(Show)

///|
pub fn StreamOptions::default() -> StreamOptions {
  {
    temperature: None,
    max_tokens: None,
    top_p: None,
    api_key: None,
    cache_retention: None,
    retry_count: None,
    retry_delay_ms: None,
    thinking_mode: None,
    thinking_budget_tokens: None,
    reasoning: None,
  }
}

///|
pub(all) struct Context {
  system_prompt : String?
  messages : Array[Message]
  tools : Array[Tool]
} derive(Show)
