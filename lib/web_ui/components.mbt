pub(all) enum ProviderConnectionState {
  Connected
  Disconnected
  Checking
} derive(Eq)

pub(all) struct ProviderConnectionStatus {
  model_count : Int
  state : ProviderConnectionState
}

pub(all) struct AttachmentTileView {
  attachment : Attachment
  show_delete : Bool
}

pub(all) struct ThinkingBlockView {
  content : String
  is_streaming : Bool
  is_expanded : Bool
}

pub(all) struct CustomProviderCardView {
  provider : CustomProvider
  status : ProviderConnectionStatus?
  show_refresh : Bool
  show_edit : Bool
  show_delete : Bool
}

pub(all) struct MessageListView {
  messages : Array[ChatMessage]
  is_streaming : Bool
}

pub(all) struct SessionListView {
  sessions : Array[SessionMetadata]
  today_iso : String
}

pub(all) struct ModelSelectorView {
  models : Array[SelectableModel]
  current_model : @ai.Model?
}

pub fn AttachmentTileView::new(
  attachment : Attachment,
  show_delete? : Bool = false
) -> AttachmentTileView {
  { attachment, show_delete }
}

pub fn ThinkingBlockView::new(
  content : String,
  is_streaming? : Bool = false,
  is_expanded? : Bool = false
) -> ThinkingBlockView {
  { content, is_streaming, is_expanded }
}

pub fn CustomProviderCardView::new(
  provider : CustomProvider,
  status? : ProviderConnectionStatus? = None,
  show_refresh? : Bool = false,
  show_edit? : Bool = true,
  show_delete? : Bool = true
) -> CustomProviderCardView {
  { provider, status, show_refresh, show_edit, show_delete }
}

pub fn MessageListView::new(
  messages : Array[ChatMessage],
  is_streaming? : Bool = false
) -> MessageListView {
  { messages: messages.copy(), is_streaming }
}

pub fn SessionListView::new(
  sessions : Array[SessionMetadata],
  today_iso : String
) -> SessionListView {
  { sessions: sessions.copy(), today_iso }
}

pub fn ModelSelectorView::new(
  models : Array[SelectableModel],
  current_model? : @ai.Model? = None
) -> ModelSelectorView {
  { models: models.copy(), current_model }
}

pub impl WebComponent for AttachmentTileView with render(self) {
  let classes = join_html_classes([
    "attachment-tile",
    "attachment-" + attachment_kind_name(self.attachment.kind),
  ])
  let children : Array[HtmlNode] = []
  children.push(attachment_tile_preview(self.attachment))
  children.push(html_element(
    "div",
    attributes=[html_class("attachment-meta")],
    children=[
      html_element("div", attributes=[html_class("attachment-name")], children=[html_text(self.attachment.file_name)]),
      html_element(
        "div",
        attributes=[html_class("attachment-size")],
        children=[html_text(format_attachment_size(self.attachment.size))],
      ),
    ],
  ))
  match attachment_excerpt(self.attachment) {
    Some(excerpt) =>
      children.push(html_element(
        "div",
        attributes=[html_class("attachment-excerpt")],
        children=[html_text(excerpt)],
      ))
    None => ()
  }
  if self.show_delete {
    children.push(html_element(
      "button",
      attributes=[
        html_class("attachment-delete"),
        html_data_attr("action", "delete-attachment"),
        html_attr("type", "button"),
      ],
      children=[html_text("Remove")],
    ))
  }
  html_element("div", attributes=[html_class(classes)], children=children)
}

pub impl WebComponent for ThinkingBlockView with render(self) {
  let header_classes = join_html_classes([
    "thinking-header",
    if self.is_streaming { "thinking-streaming" } else { "" },
  ])
  let children : Array[HtmlNode] = [
    html_element(
      "div",
      attributes=[html_class(header_classes)],
      children=[html_text("Thinking...")],
    ),
  ]
  if self.is_expanded {
    children.push(html_element(
      "pre",
      attributes=[html_class("thinking-content")],
      children=[html_text(self.content)],
    ))
  }
  html_element(
    "section",
    attributes=[html_class("thinking-block"), html_data_attr("expanded", bool_string(self.is_expanded))],
    children=children,
  )
}

pub impl WebComponent for CustomProviderCardView with render(self) {
  let provider = self.provider
  let meta_parts : Array[HtmlNode] = [
    html_element(
      "span",
      attributes=[html_class("provider-type")],
      children=[html_text(provider_type_label(provider.provider_type))],
    ),
  ]
  if provider.base_url.length() > 0 {
    meta_parts.push(html_text(" "))
    meta_parts.push(html_element(
      "span",
      attributes=[html_class("provider-url")],
      children=[html_text(provider.base_url)],
    ))
  }
  let children : Array[HtmlNode] = [
    html_element("h3", attributes=[html_class("provider-name")], children=[html_text(provider.name)]),
    html_element("div", attributes=[html_class("provider-meta")], children=meta_parts),
    custom_provider_status_node(provider, self.status),
    custom_provider_actions(self),
  ]
  html_element("article", attributes=[html_class("custom-provider-card")], children=children)
}

pub impl WebComponent for MessageListView with render(self) {
  let items : Array[HtmlNode] = []
  for message in self.messages {
    match render_message_item(message) {
      Some(node) => items.push(node)
      None => ()
    }
  }
  if self.is_streaming {
    items.push(html_element(
      "div",
      attributes=[html_class("message-streaming-indicator")],
      children=[html_text("Streaming...")],
    ))
  }
  html_element("section", attributes=[html_class("message-list")], children=items)
}

pub impl WebComponent for SessionListView with render(self) {
  let items : Array[HtmlNode] = []
  for session in self.sessions {
    items.push(html_element(
      "article",
      attributes=[html_class("session-list-item"), html_data_attr("session-id", session.id)],
      children=[
        html_element("h3", attributes=[html_class("session-title")], children=[html_text(session.title)]),
        html_element(
          "div",
          attributes=[html_class("session-meta")],
          children=[
            html_text(format_relative_date(session.last_modified, self.today_iso)),
            html_text(" "),
            html_text(session.message_count.to_string() + " messages"),
            html_text(" "),
            html_text(format_usage(session.usage)),
          ],
        ),
        html_element("p", attributes=[html_class("session-preview")], children=[html_text(session.preview)]),
      ],
    ))
  }
  html_element("section", attributes=[html_class("session-list")], children=items)
}

pub impl WebComponent for ModelSelectorView with render(self) {
  let items : Array[HtmlNode] = []
  for entry in self.models {
    let badges : Array[HtmlNode] = []
    if model_selector_is_current(entry.model, self.current_model) {
      badges.push(model_badge("current"))
    }
    if entry.model.reasoning {
      badges.push(model_badge("thinking"))
    }
    if model_supports_vision(entry.model) {
      badges.push(model_badge("vision"))
    }

    let item_children : Array[HtmlNode] = [
      html_element("div", attributes=[html_class("model-provider")], children=[html_text(entry.provider)]),
      html_element("div", attributes=[html_class("model-name")], children=[html_text(entry.model.name)]),
      html_element(
        "div",
        attributes=[html_class("model-id")],
        children=[html_text(entry.model.id)],
      ),
    ]
    if badges.length() > 0 {
      item_children.push(html_element(
        "div",
        attributes=[html_class("model-badges")],
        children=badges,
      ))
    }
    item_children.push(html_element(
      "div",
      attributes=[html_class("model-cost")],
      children=[html_text(format_model_cost(entry.model.cost))],
    ))

    items.push(html_element(
      "article",
      attributes=[html_class("model-selector-item"), html_data_attr("provider", entry.provider)],
      children=item_children,
    ))
  }
  html_element("section", attributes=[html_class("model-selector")], children=items)
}

fn attachment_tile_preview(attachment : Attachment) -> HtmlNode {
  match attachment_preview_url(attachment) {
    Some(url) => html_element(
      "img",
      attributes=[
        html_class("attachment-preview"),
        html_attr("src", url),
        html_attr("alt", attachment.file_name),
      ],
    )
    None => html_element(
      "div",
      attributes=[html_class("attachment-fallback")],
      children=[html_text(attachment_fallback_label(attachment))],
    )
  }
}

fn attachment_preview_url(attachment : Attachment) -> String? {
  match attachment.kind {
    AttachmentKind::Image => Some("data:" + attachment.mime_type + ";base64," + attachment.content_base64)
    AttachmentKind::Document =>
      match attachment.preview_base64 {
        Some(preview) => Some("data:image/png;base64," + preview)
        None => None
      }
  }
}

fn attachment_fallback_label(attachment : Attachment) -> String {
  if attachment.mime_type == "application/pdf" {
    "PDF"
  } else if attachment.mime_type.contains("sheet") || attachment.file_name.to_lower().has_suffix(".xlsx") {
    "Sheet"
  } else {
    "Doc"
  }
}

fn format_attachment_size(size : Int) -> String {
  if size < 1024 {
    size.to_string() + " B"
  } else if size < 1024 * 1024 {
    (size / 1024).to_string() + " KB"
  } else {
    (size / (1024 * 1024)).to_string() + " MB"
  }
}

fn attachment_excerpt(attachment : Attachment) -> String? {
  match attachment.extracted_text {
    Some(text) => {
      let normalized = text.replace_all(old="\n", new=" ").replace_all(old="\r", new=" ").trim().to_string()
      if normalized.length() == 0 {
        None
      } else if normalized.length() <= 120 {
        Some(normalized)
      } else {
        Some(normalized[:117].to_string() + "...")
      }
    }
    None => None
  }
}

fn attachment_kind_name(kind : AttachmentKind) -> String {
  match kind {
    AttachmentKind::Image => "image"
    AttachmentKind::Document => "document"
  }
}

fn bool_string(value : Bool) -> String {
  if value { "true" } else { "false" }
}

fn custom_provider_status_node(
  provider : CustomProvider,
  status : ProviderConnectionStatus?
) -> HtmlNode {
  if !is_auto_discovery_provider_type(provider.provider_type) {
    let count = custom_provider_models(provider).length()
    return html_element(
      "div",
      attributes=[html_class("provider-status")],
      children=[html_text("Models: " + count.to_string())],
    )
  }

  match status {
    Some(value) =>
      html_element(
        "div",
        attributes=[html_class("provider-status provider-status-" + provider_connection_state_name(value.state))],
        children=[html_text(provider_connection_text(value))],
      )
    None =>
      html_element(
        "div",
        attributes=[html_class("provider-status provider-status-unknown")],
        children=[html_text("Status unknown")],
      )
  }
}

fn custom_provider_actions(view : CustomProviderCardView) -> HtmlNode {
  let actions : Array[HtmlNode] = []
  if view.show_refresh && is_auto_discovery_provider_type(view.provider.provider_type) {
    actions.push(component_action_button("refresh-provider", "Refresh"))
  }
  if view.show_edit {
    actions.push(component_action_button("edit-provider", "Edit"))
  }
  if view.show_delete {
    actions.push(component_action_button("delete-provider", "Delete"))
  }
  html_element("div", attributes=[html_class("provider-actions")], children=actions)
}

fn component_action_button(action : String, label : String) -> HtmlNode {
  html_element(
    "button",
    attributes=[
      html_class("component-action"),
      html_data_attr("action", action),
      html_attr("type", "button"),
    ],
    children=[html_text(label)],
  )
}

fn provider_connection_text(status : ProviderConnectionStatus) -> String {
  match status.state {
    ProviderConnectionState::Connected => status.model_count.to_string() + " models"
    ProviderConnectionState::Checking => "Checking..."
    ProviderConnectionState::Disconnected => "Disconnected"
  }
}

fn provider_connection_state_name(state : ProviderConnectionState) -> String {
  match state {
    ProviderConnectionState::Connected => "connected"
    ProviderConnectionState::Disconnected => "disconnected"
    ProviderConnectionState::Checking => "checking"
  }
}

fn render_message_item(message : ChatMessage) -> HtmlNode? {
  match message {
    Artifact(_) => None
    UserWithAttachments(user_message) =>
      Some(html_element(
        "article",
        attributes=[html_class("message message-user")],
        children=[
          html_element(
            "div",
            attributes=[html_class("message-body")],
            children=[html_text(component_content_blocks_text(user_message.content))],
          ),
          message_attachments_node(user_message.attachments),
        ],
      ))
    Standard(standard_message) =>
      match standard_message {
        @ai.Message::User(user) =>
          Some(html_element(
            "article",
            attributes=[html_class("message message-user")],
            children=[
              html_element("div", attributes=[html_class("message-body")], children=[html_text(component_content_blocks_text(user.content))]),
            ],
          ))
        @ai.Message::Assistant(assistant) =>
          Some(html_element(
            "article",
            attributes=[html_class("message message-assistant")],
            children=assistant_message_children(assistant),
          ))
        @ai.Message::ToolResult(tool_result) =>
          Some(html_element(
            "article",
            attributes=[html_class(
              join_html_classes([
                "message",
                "message-tool-result",
                if tool_result.error { "message-error" } else { "" },
              ]),
            )],
            children=[
              html_element(
                "div",
                attributes=[html_class("tool-result-name")],
                children=[html_text(tool_result.tool_name)],
              ),
              html_element(
                "pre",
                attributes=[html_class("tool-result-body")],
                children=[html_text(component_content_blocks_text(tool_result.content))],
              ),
            ],
          ))
      }
  }
}

fn assistant_message_children(assistant : @ai.AssistantMessage) -> Array[HtmlNode] {
  let children : Array[HtmlNode] = []
  for block in assistant.content {
    match block {
      @ai.ContentBlock::Text(text) =>
        children.push(html_element(
          "div",
          attributes=[html_class("assistant-text")],
          children=[html_text(text)],
        ))
      @ai.ContentBlock::Thinking(text) =>
        children.push(ThinkingBlockView::new(text, is_expanded=true).render())
      @ai.ContentBlock::Image(image) =>
        children.push(html_element(
          "img",
          attributes=[
            html_class("assistant-image"),
            html_attr("src", "data:" + image_mime_name(image.mime_type) + ";base64," + image.data),
            html_attr("alt", "assistant image"),
          ],
        ))
      @ai.ContentBlock::ToolCall(tool_call) =>
        children.push(html_element(
          "div",
          attributes=[html_class("assistant-tool-call")],
          children=[
            html_element("div", attributes=[html_class("tool-call-name")], children=[html_text(tool_call.name)]),
            html_element(
              "pre",
              attributes=[html_class("tool-call-arguments")],
              children=[html_text(tool_call.arguments.stringify(escape_slash=false))],
            ),
          ],
        ))
    }
  }
  if assistant.usage.total_tokens > 0 || assistant.usage.cost.total > 0.0 {
    children.push(html_element(
      "div",
      attributes=[html_class("assistant-usage")],
      children=[html_text(format_usage(assistant.usage))],
    ))
  }
  children
}

fn message_attachments_node(attachments : Array[Attachment]) -> HtmlNode {
  let tiles : Array[HtmlNode] = []
  for attachment in attachments {
    tiles.push(AttachmentTileView::new(attachment).render())
  }
  html_element("div", attributes=[html_class("message-attachments")], children=tiles)
}

fn model_selector_is_current(model : @ai.Model, current_model : @ai.Model?) -> Bool {
  match current_model {
    Some(current) => @ai.models_are_equal(model, current)
    None => false
  }
}

fn model_supports_vision(model : @ai.Model) -> Bool {
  for modality in model.input_modalities {
    if modality == @ai.InputModality::Image {
      return true
    }
  }
  false
}

fn model_badge(text : String) -> HtmlNode {
  html_element("span", attributes=[html_class("model-badge")], children=[html_text(text)])
}

fn image_mime_name(mime_type : @ai.ImageMimeType) -> String {
  match mime_type {
    @ai.ImageMimeType::Jpeg => "image/jpeg"
    @ai.ImageMimeType::Png => "image/png"
    @ai.ImageMimeType::Gif => "image/gif"
    @ai.ImageMimeType::Webp => "image/webp"
  }
}

fn component_content_blocks_text(content : Array[@ai.ContentBlock]) -> String {
  let texts : Array[String] = []
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) => {
        let normalized = text.replace_all(old="\n", new=" ").replace_all(old="\r", new=" ").trim().to_string()
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
