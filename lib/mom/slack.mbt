/// Slack adapter configuration
pub(all) struct SlackAdapterConfig {
  app_token : String
  bot_token : String
  base_url : String
}

/// Slack platform adapter — a PlatformAdapter implementation that talks to the
/// Slack Web API and Socket Mode API.  The current implementation is a
/// well-structured stub: it stores tokens and metadata but returns clear
/// "not connected" errors for any network operations.  This gives a compile-
/// and-test-ready skeleton that can be filled in once MoonBit gains HTTP /
/// WebSocket FFI.
pub(all) struct SlackPlatformAdapter {
  config : SlackAdapterConfig
  adapter_name : String
  mut connected : Bool
  mut channels : Array[ChannelInfo]
  mut users : Array[UserInfo]
  mut sent_messages : Array[AdapterSentMessage]
}

/// Create a new Slack platform adapter.
///
/// `adapter_name` defaults to `"slack"` but can be overridden for multi-
/// workspace setups.
pub fn SlackPlatformAdapter::new(
  app_token : String,
  bot_token : String,
  base_url? : String = "https://slack.com/api",
  adapter_name? : String = "slack"
) -> SlackPlatformAdapter {
  {
    config: { app_token, bot_token, base_url },
    adapter_name,
    connected: false,
    channels: [],
    users: [],
    sent_messages: [],
  }
}

/// Attempt to connect to Slack.
///
/// Currently returns an error because WebSocket/HTTP FFI is not yet
/// available in MoonBit.
pub fn SlackPlatformAdapter::connect(
  self : SlackPlatformAdapter
) -> Result[Unit, String] {
  ignore(self)
  Err("Slack adapter connect not yet implemented: WebSocket FFI required")
}

/// Send a text message to a Slack channel.
///
/// Returns an error while the adapter is a stub.
pub fn SlackPlatformAdapter::send_text(
  self : SlackPlatformAdapter,
  channel_id : String,
  text : String
) -> Result[AdapterSentMessage, String] {
  if !self.connected {
    return Err("Slack adapter not connected: call connect() first")
  }
  ignore(channel_id)
  ignore(text)
  Err("Slack adapter send_text not yet implemented")
}

/// Disconnect from Slack.
pub fn SlackPlatformAdapter::disconnect(
  self : SlackPlatformAdapter
) -> Unit {
  self.connected = false
}

// ---------------------------------------------------------------------------
// PlatformAdapter trait implementation
// ---------------------------------------------------------------------------

pub impl PlatformAdapter for SlackPlatformAdapter with name(self) {
  self.adapter_name
}

pub impl PlatformAdapter for SlackPlatformAdapter with start(self) {
  self.connected = true
}

pub impl PlatformAdapter for SlackPlatformAdapter with stop(self) {
  self.connected = false
}

pub impl PlatformAdapter for SlackPlatformAdapter with get_channels(self) {
  self.channels.copy()
}

pub impl PlatformAdapter for SlackPlatformAdapter with get_users(self) {
  self.users.copy()
}

pub impl PlatformAdapter for SlackPlatformAdapter with send_message(self, outbound) {
  let sent : AdapterSentMessage = {
    id: "slack-" + (self.sent_messages.length() + 1).to_string(),
    channel_id: outbound.channel_id,
    text: outbound.text,
    reply_to: outbound.reply_to,
  }
  self.sent_messages.push(sent)
  Ok(sent)
}

// ---------------------------------------------------------------------------
// Convenience factory — mirrors the pi-mono SlackBot constructor
// ---------------------------------------------------------------------------

/// Create a Slack adapter with pre-populated channel and user lists.
///
/// This is useful for tests and for real usage where the channel/user lists
/// have been fetched externally (e.g. via a future HTTP client).
pub fn slack_adapter_with_metadata(
  app_token : String,
  bot_token : String,
  channels : Array[ChannelInfo],
  users : Array[UserInfo],
  base_url? : String = "https://slack.com/api",
  adapter_name? : String = "slack"
) -> SlackPlatformAdapter {
  let adapter = SlackPlatformAdapter::new(app_token, bot_token, base_url~, adapter_name~)
  adapter.channels = channels.copy()
  adapter.users = users.copy()
  adapter
}
