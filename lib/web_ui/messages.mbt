pub fn image_attachment(
  id : String,
  file_name : String,
  mime_type : String,
  size : Int,
  content_base64 : String,
  preview_base64? : String? = None
) -> Attachment {
  {
    id,
    kind: AttachmentKind::Image,
    file_name,
    mime_type,
    size,
    content_base64,
    extracted_text: None,
    preview_base64: match preview_base64 {
      Some(value) => Some(value)
      None => Some(content_base64)
    },
  }
}

pub fn document_attachment(
  id : String,
  file_name : String,
  mime_type : String,
  size : Int,
  content_base64 : String,
  extracted_text? : String? = None,
  preview_base64? : String? = None
) -> Attachment {
  {
    id,
    kind: AttachmentKind::Document,
    file_name,
    mime_type,
    size,
    content_base64,
    extracted_text,
    preview_base64,
  }
}

pub fn user_message_with_attachments(
  text : String,
  attachments? : Array[Attachment] = [],
  timestamp? : Double = 0.0
) -> ChatMessage {
  UserWithAttachments({
    content: [@ai.ContentBlock::Text(text)],
    timestamp,
    attachments: attachments.copy(),
  })
}

pub fn convert_attachments(attachments : Array[Attachment]) -> Array[@ai.ContentBlock] {
  let content : Array[@ai.ContentBlock] = []
  for attachment in attachments {
    match attachment.kind {
      AttachmentKind::Image =>
        content.push(@ai.ContentBlock::Image({
          mime_type: attachment_mime_type(attachment.mime_type),
          data: attachment.content_base64,
          url: None,
        }))
      AttachmentKind::Document =>
        match attachment.extracted_text {
          Some(text) if text.trim().length() > 0 =>
            content.push(@ai.ContentBlock::Text(
              "\n\n[Document: " + attachment.file_name + "]\n" + text,
            ))
          _ => ()
        }
    }
  }
  content
}

pub fn is_user_message_with_attachments(message : ChatMessage) -> Bool {
  message is UserWithAttachments(_)
}

pub fn is_artifact_message(message : ChatMessage) -> Bool {
  message is Artifact(_)
}

pub fn default_convert_to_llm(messages : Array[ChatMessage]) -> Array[@ai.Message] {
  let converted : Array[@ai.Message] = []
  for message in messages {
    match message {
      Standard(llm_message) => converted.push(llm_message)
      UserWithAttachments(user_message) => {
        let content = user_message.content.copy()
        let attachment_content = convert_attachments(user_message.attachments)
        for block in attachment_content {
          content.push(block)
        }
        converted.push(@ai.Message::User({ content: content }))
      }
      Artifact(_) => ()
    }
  }
  converted
}

pub fn chat_message_text(message : ChatMessage, include_assistant? : Bool = true) -> String {
  match message {
    Standard(llm_message) =>
      match llm_message {
        @ai.Message::User(user_message) => content_blocks_text(user_message.content)
        @ai.Message::Assistant(assistant_message) =>
          if include_assistant {
            content_blocks_text(assistant_message.content)
          } else {
            ""
          }
        @ai.Message::ToolResult(_) => ""
      }
    UserWithAttachments(user_message) => content_blocks_text(user_message.content)
    Artifact(_) => ""
  }
}

fn content_blocks_text(content : Array[@ai.ContentBlock]) -> String {
  let texts : Array[String] = []
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) => {
        let normalized = normalize_single_line(text)
        if normalized.length() > 0 {
          texts.push(normalized)
        }
      }
      @ai.ContentBlock::Thinking(_) => ()
      @ai.ContentBlock::Image(_) => ()
      @ai.ContentBlock::ToolCall(_) => ()
    }
  }
  texts.join(" ")
}

fn normalize_single_line(text : String) -> String {
  text.replace_all(old="\n", new=" ").replace_all(old="\r", new=" ").trim().to_string()
}

fn attachment_mime_type(mime_type : String) -> @ai.ImageMimeType {
  match mime_type.to_lower() {
    "image/jpeg" => @ai.ImageMimeType::Jpeg
    "image/jpg" => @ai.ImageMimeType::Jpeg
    "image/gif" => @ai.ImageMimeType::Gif
    "image/webp" => @ai.ImageMimeType::Webp
    _ => @ai.ImageMimeType::Png
  }
}
