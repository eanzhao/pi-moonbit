pub fn InMemoryPlatformAdapter::new(
  adapter_name : String,
  channels : Array[ChannelInfo],
  users : Array[UserInfo]
) -> InMemoryPlatformAdapter {
  {
    adapter_name,
    channels: channels.copy(),
    users: users.copy(),
    started: false,
    sent_messages: [],
    observed_events: [],
  }
}

pub fn[T : PlatformAdapter] run_mom_turn_with_adapter(
  adapter : T,
  mom : MomAgent,
  message : ChannelMessage,
  channel_memory? : String? = None,
  skills? : Array[MomSkill] = [],
) -> Result[MomRunResult, MomAgentError] {
  let context : ChannelContext = {
    adapter: adapter.name(),
    channels: adapter.get_channels(),
    users: adapter.get_users(),
  }
  let result = match mom.handle_message(
    message,
    context,
    channel_memory~,
    skills~,
    on_event=Some(fn(event) {
      adapter.handle_agent_event(message, event)
    }),
  ) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let outbound = outbound_message_for_result(message, result)
  match outbound {
    Some(outbound_message) =>
      match adapter.send_message(outbound_message) {
        Ok(_) => Ok(result)
        Err(message) => Err(AdapterFailed(message))
      }
    None => Ok(result)
  }
}

fn outbound_message_for_result(
  incoming : ChannelMessage,
  result : MomRunResult
) -> AdapterOutboundMessage? {
  let text = if result.assistant_text.length() > 0 {
    result.assistant_text
  } else {
    result.error_message.unwrap_or("")
  }
  if text.length() == 0 {
    None
  } else {
    Some({
      channel_id: incoming.channel_id,
      text,
      reply_to: incoming.reply_to,
    })
  }
}

pub impl PlatformAdapter for InMemoryPlatformAdapter with name(self) {
  self.adapter_name
}

pub impl PlatformAdapter for InMemoryPlatformAdapter with start(self) {
  self.started = true
}

pub impl PlatformAdapter for InMemoryPlatformAdapter with stop(self) {
  self.started = false
}

pub impl PlatformAdapter for InMemoryPlatformAdapter with get_channels(self) {
  self.channels.copy()
}

pub impl PlatformAdapter for InMemoryPlatformAdapter with get_users(self) {
  self.users.copy()
}

pub impl PlatformAdapter for InMemoryPlatformAdapter with send_message(self, outbound) {
  let sent : AdapterSentMessage = {
    id: "sent-" + (self.sent_messages.length() + 1).to_string(),
    channel_id: outbound.channel_id,
    text: outbound.text,
    reply_to: outbound.reply_to,
  }
  self.sent_messages.push(sent)
  Ok(sent)
}

pub impl PlatformAdapter for InMemoryPlatformAdapter with handle_agent_event(self, _message, event) {
  self.observed_events.push(in_memory_adapter_event_name(event))
}

fn in_memory_adapter_event_name(event : @agent.AgentEvent) -> String {
  match event {
    @agent.AgentEvent::AgentStart => "agent_start"
    @agent.AgentEvent::AgentEnd(_) => "agent_end"
    @agent.AgentEvent::TurnStart => "turn_start"
    @agent.AgentEvent::TurnEnd(_) => "turn_end"
    @agent.AgentEvent::MessageStart(_) => "message_start"
    @agent.AgentEvent::MessageUpdate(_) => "message_update"
    @agent.AgentEvent::MessageEnd(_) => "message_end"
    @agent.AgentEvent::ToolExecutionStart(_) => "tool_execution_start"
    @agent.AgentEvent::ToolExecutionUpdate(_) => "tool_execution_update"
    @agent.AgentEvent::ToolExecutionEnd(_) => "tool_execution_end"
  }
}

impl PlatformAdapter with start(_self) {
  ()
}

impl PlatformAdapter with stop(_self) {
  ()
}

impl PlatformAdapter with handle_agent_event(_self, _message, _event) {
  ()
}
