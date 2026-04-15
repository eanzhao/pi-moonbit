///|
pub(all) enum ImageMimeType {
  Jpeg
  Png
  Gif
  Webp
} derive(Show, Eq)

///|
pub(all) struct ImageContent {
  mime_type : ImageMimeType
  data : String
  url : String?
} derive(Show, Eq)

///|
pub(all) struct ToolCall {
  id : String
  name : String
  arguments : Json
} derive(Show)

///|
pub(all) enum ContentBlock {
  Text(String)
  Thinking(String)
  Image(ImageContent)
  ToolCall(ToolCall)
} derive(Show)

///|
pub(all) enum StopReason {
  Stop
  Length
  ToolUse
  Error
  Aborted
} derive(Show, Eq)

///|
pub(all) struct CostBreakdown {
  input : Double
  output : Double
  cache_read : Double
  cache_write : Double
  total : Double
} derive(Show, Eq)

///|
pub(all) struct Usage {
  input : Int
  output : Int
  cache_read : Int
  cache_write : Int
  total_tokens : Int
  cost : CostBreakdown
} derive(Show, Eq)

///|
pub fn Usage::zero() -> Usage {
  {
    input: 0,
    output: 0,
    cache_read: 0,
    cache_write: 0,
    total_tokens: 0,
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0, total: 0.0 },
  }
}

///|
pub(all) struct UserMessage {
  content : Array[ContentBlock]
} derive(Show)

///|
pub(all) struct AssistantMessage {
  content : Array[ContentBlock]
  api : ApiId
  provider : ProviderId
  model : String
  usage : Usage
  stop_reason : StopReason
  error_message : String?
  timestamp : Double
} derive(Show)

///|
pub(all) struct ToolResultMessage {
  content : Array[ContentBlock]
  tool_call_id : String
  tool_name : String
  error : Bool
} derive(Show)

///|
pub(all) enum Message {
  User(UserMessage)
  Assistant(AssistantMessage)
  ToolResult(ToolResultMessage)
} derive(Show)
