///| 图片的 MIME 类型。
pub(all) enum ImageMimeType {
  Jpeg
  Png
  Gif
  Webp
} derive(Show, Eq)

///| 图片内容，包含 base64 编码的数据和可选的原始 URL。
pub(all) struct ImageContent {
  mime_type : ImageMimeType
  /// base64 编码的图片数据
  data : String
  /// 图片的原始 URL（如果有）
  url : String?
} derive(Show, Eq)

///| 工具调用信息，由 LLM 在响应中生成。
pub(all) struct ToolCall {
  /// 调用的唯一标识，用于关联调用与结果
  id : String
  /// 工具名称
  name : String
  /// 工具参数（JSON 格式）
  arguments : Json
} derive(Show)

///| 消息内容块，对话中消息的组成单元。
/// 一条消息可以包含多个不同类型的内容块。
pub(all) enum ContentBlock {
  /// 普通文本
  Text(String)
  /// 思维链/推理过程
  Thinking(String)
  /// 图片内容
  Image(ImageContent)
  /// 工具调用请求
  ToolCall(ToolCall)
} derive(Show)

///| LLM 停止生成的原因。
pub(all) enum StopReason {
  /// 自然结束
  Stop
  /// 达到最大 token 限制
  Length
  /// 需要调用工具
  ToolUse
  /// 发生错误
  Error
  /// 被用户中止
  Aborted
} derive(Show, Eq)

///| 费用明细，按输入/输出/缓存分类（单位：美元）。
pub(all) struct CostBreakdown {
  input : Double
  output : Double
  cache_read : Double
  cache_write : Double
  total : Double
} derive(Show, Eq)

///| Token 用量统计及对应的费用。
pub(all) struct Usage {
  /// 输入 token 数
  input : Int
  /// 输出 token 数
  output : Int
  /// 从缓存读取的 token 数
  cache_read : Int
  /// 写入缓存的 token 数
  cache_write : Int
  /// 总 token 数
  total_tokens : Int
  /// 费用明细
  cost : CostBreakdown
} derive(Show, Eq)

///| 创建一个所有字段为零的 Usage 实例。
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

///| 用户发送的消息。
pub(all) struct UserMessage {
  content : Array[ContentBlock]
} derive(Show)

///| LLM 返回的助手消息，包含响应内容及元数据。
pub(all) struct AssistantMessage {
  /// 响应内容块列表
  content : Array[ContentBlock]
  /// 使用的 API 协议
  api : ApiId
  /// 使用的供应商
  provider : ProviderId
  /// 使用的模型 ID
  model : String
  /// Token 用量和费用
  usage : Usage
  /// 停止原因
  stop_reason : StopReason
  /// 错误消息（仅在出错时存在）
  error_message : String?
  /// 响应时间戳（Unix 秒）
  timestamp : Double
} derive(Show)

///| 工具执行结果消息，用于将工具的输出反馈给 LLM。
pub(all) struct ToolResultMessage {
  /// 工具输出内容
  content : Array[ContentBlock]
  /// 对应的工具调用 ID
  tool_call_id : String
  /// 工具名称
  tool_name : String
  /// 执行是否出错
  error : Bool
} derive(Show)

///| 对话消息的统一类型，构成对话历史的基本单元。
pub(all) enum Message {
  User(UserMessage)
  Assistant(AssistantMessage)
  ToolResult(ToolResultMessage)
} derive(Show)
