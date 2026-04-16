pub(all) enum ToolCallStatus {
  Pending
  Running
  Completed
  Failed
} derive(Show)

pub(all) struct CodeBlock {
  language : String
  code : String
} derive(Show)

pub(all) struct ToolCallBlock {
  id : String
  name : String
  arguments : String
  status : ToolCallStatus
} derive(Show)

pub(all) struct ToolResultBlock {
  tool_call_id : String
  content : String
  is_error : Bool
} derive(Show)

pub(all) struct ImageBlock {
  url : String
  alt : String
} derive(Show)

pub(all) struct AttachmentBlock {
  name : String
  mime_type : String
  url : String
} derive(Show)

pub(all) struct Usage {
  input_tokens : Int
  output_tokens : Int
} derive(Show)

pub(all) enum RenderableBlock {
  Text(String)
  Code(CodeBlock)
  ToolCall(ToolCallBlock)
  ToolResult(ToolResultBlock)
  Image(ImageBlock)
  Attachment(AttachmentBlock)
  Thinking(String)
} derive(Show)

pub(all) struct RenderableMessage {
  id : String
  role : String
  content : Array[RenderableBlock]
  timestamp : Int64
  model : String
  usage : Usage?
  is_streaming : Bool
  is_error : Bool
} derive(Show)

pub fn chat_message_to_renderable(
  message : ChatMessage,
  is_streaming? : Bool = false
) -> RenderableMessage {
  match message {
    Standard(message) => ai_message_to_renderable(message, is_streaming=is_streaming)
    UserWithAttachments(message) => {
      let content = renderable_blocks_from_ai_content(
        message.content,
        if is_streaming {
          ToolCallStatus::Running
        } else {
          ToolCallStatus::Pending
        },
      )
      for attachment in message.attachments {
        content.push(RenderableBlock::Attachment(renderable_attachment_block(attachment)))
      }
      let timestamp = message.timestamp.to_int64()
      {
        id: renderable_message_id("user", timestamp, content.length(), ""),
        role: "user",
        content,
        timestamp,
        model: "",
        usage: None,
        is_streaming,
        is_error: false,
      }
    }
    Artifact(message) => {
      let content : Array[RenderableBlock] = [RenderableBlock::Text(renderable_artifact_summary(message))]
      match message.content {
        Some(code) if code.length() > 0 =>
          content.push(RenderableBlock::Code({
            language: renderable_code_language(message.filename),
            code,
          }))
        _ => ()
      }
      {
        id: "artifact:" + message.filename,
        role: "artifact",
        content,
        timestamp: 0L,
        model: "",
        usage: None,
        is_streaming,
        is_error: false,
      }
    }
  }
}

pub fn ai_message_to_renderable(
  message : @ai.Message,
  model? : String = "",
  is_streaming? : Bool = false
) -> RenderableMessage {
  match message {
    @ai.Message::User(message) => {
      let content = renderable_blocks_from_ai_content(
        message.content,
        if is_streaming {
          ToolCallStatus::Running
        } else {
          ToolCallStatus::Pending
        },
      )
      {
        id: renderable_message_id("user", 0L, content.length(), model),
        role: "user",
        content,
        timestamp: 0L,
        model,
        usage: None,
        is_streaming,
        is_error: false,
      }
    }
    @ai.Message::Assistant(message) => {
      let resolved_model = if model.length() > 0 { model } else { message.model }
      let content = renderable_blocks_from_ai_content(
        message.content,
        if is_streaming {
          ToolCallStatus::Running
        } else if message.stop_reason == @ai.StopReason::ToolUse {
          ToolCallStatus::Pending
        } else {
          ToolCallStatus::Completed
        },
      )
      match message.error_message {
        Some(error) if error.trim().length() > 0 =>
          content.push(RenderableBlock::Text(error))
        _ => ()
      }
      let timestamp = message.timestamp.to_int64()
      {
        id: renderable_message_id("assistant", timestamp, content.length(), resolved_model),
        role: "assistant",
        content,
        timestamp,
        model: resolved_model,
        usage: Some({
          input_tokens: message.usage.input,
          output_tokens: message.usage.output,
        }),
        is_streaming,
        is_error: message.stop_reason == @ai.StopReason::Error || message.error_message is Some(_),
      }
    }
    @ai.Message::ToolResult(message) => {
      let content : Array[RenderableBlock] = [RenderableBlock::ToolResult({
        tool_call_id: message.tool_call_id,
        content: renderable_tool_result_content(message.content),
        is_error: message.error,
      })]
      {
        id: "tool:" + message.tool_call_id,
        role: "tool",
        content,
        timestamp: 0L,
        model,
        usage: None,
        is_streaming,
        is_error: message.error,
      }
    }
  }
}

fn renderable_blocks_from_ai_content(
  content : Array[@ai.ContentBlock],
  tool_call_status : ToolCallStatus
) -> Array[RenderableBlock] {
  let blocks : Array[RenderableBlock] = []
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) =>
        blocks.push(RenderableBlock::Text(text))
      @ai.ContentBlock::Thinking(text) =>
        blocks.push(RenderableBlock::Thinking(text))
      @ai.ContentBlock::Image(image) =>
        blocks.push(RenderableBlock::Image(renderable_image_block(image)))
      @ai.ContentBlock::ToolCall(tool_call) =>
        blocks.push(RenderableBlock::ToolCall({
          id: tool_call.id,
          name: tool_call.name,
          arguments: tool_call.arguments.stringify(escape_slash=false),
          status: tool_call_status,
        }))
    }
  }
  blocks
}

fn renderable_attachment_block(attachment : Attachment) -> AttachmentBlock {
  {
    name: attachment.file_name,
    mime_type: attachment.mime_type,
    url: "data:" + attachment.mime_type + ";base64," + attachment.content_base64,
  }
}

fn renderable_image_block(image : @ai.ImageContent) -> ImageBlock {
  let url = match image.url {
    Some(url) if url.length() > 0 => url
    _ => "data:" + renderable_image_mime_name(image.mime_type) + ";base64," + image.data
  }
  { url, alt: "image" }
}

fn renderable_image_mime_name(mime_type : @ai.ImageMimeType) -> String {
  match mime_type {
    @ai.ImageMimeType::Jpeg => "image/jpeg"
    @ai.ImageMimeType::Png => "image/png"
    @ai.ImageMimeType::Gif => "image/gif"
    @ai.ImageMimeType::Webp => "image/webp"
  }
}

fn renderable_tool_result_content(content : Array[@ai.ContentBlock]) -> String {
  let parts : Array[String] = []
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) =>
        if text.length() > 0 {
          parts.push(text)
        }
      @ai.ContentBlock::Thinking(text) =>
        if text.length() > 0 {
          parts.push(text)
        }
      @ai.ContentBlock::Image(_) => parts.push("[image]")
      @ai.ContentBlock::ToolCall(tool_call) =>
        parts.push(tool_call.name + "(" + tool_call.arguments.stringify(escape_slash=false) + ")")
    }
  }
  parts.join("\n\n")
}

fn renderable_artifact_summary(message : ArtifactMessage) -> String {
  renderable_artifact_action_name(message.action) + ": " + message.filename
}

fn renderable_artifact_action_name(action : ArtifactAction) -> String {
  match action {
    ArtifactAction::Create => "create"
    ArtifactAction::Update => "update"
    ArtifactAction::Delete => "delete"
  }
}

fn renderable_code_language(filename : String) -> String {
  let lower = filename.to_lower()
  if lower.has_suffix(".html") {
    "html"
  } else if lower.has_suffix(".css") {
    "css"
  } else if lower.has_suffix(".js") {
    "javascript"
  } else if lower.has_suffix(".json") {
    "json"
  } else if lower.has_suffix(".md") {
    "markdown"
  } else if lower.has_suffix(".py") {
    "python"
  } else if lower.has_suffix(".ts") {
    "typescript"
  } else {
    ""
  }
}

fn renderable_message_id(
  role : String,
  timestamp : Int64,
  content_count : Int,
  model : String
) -> String {
  let suffix = if model.length() > 0 { ":" + model } else { "" }
  role + ":" + timestamp.to_string() + ":" + content_count.to_string() + suffix
}
