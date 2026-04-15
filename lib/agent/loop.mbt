priv struct PreparedToolCall {
  tool_call : @ai.ToolCall
  tool : AgentTool
  args : Json
}

priv struct ImmediateToolCallOutcome {
  result : AgentToolResult
  is_error : Bool
}

priv struct ExecutedToolCallOutcome {
  result : AgentToolResult
  is_error : Bool
}

///| 运行一个新的 agent loop，并返回本次新增消息。
pub fn run_agent_loop(
  prompts : Array[@ai.Message],
  context : AgentContext,
  config : AgentLoopConfig,
  emit : (AgentEvent) -> Unit
) -> Result[Array[@ai.Message], AgentError] {
  let new_messages = prompts.copy()
  let current_context : AgentContext = {
    system_prompt: context.system_prompt,
    messages: context.messages.copy(),
    tools: context.tools.copy(),
  }
  for prompt in prompts {
    current_context.messages.push(prompt)
  }
  emit(AgentStart)
  emit(TurnStart)
  for prompt in prompts {
    emit(MessageStart(prompt))
    emit(MessageEnd(prompt))
  }
  match run_loop(current_context, new_messages, config, emit) {
    Ok(_) => Ok(new_messages)
    Err(error) => Err(error)
  }
}

///| 从已有上下文继续执行 agent loop。
pub fn run_agent_loop_continue(
  context : AgentContext,
  config : AgentLoopConfig,
  emit : (AgentEvent) -> Unit
) -> Result[Array[@ai.Message], AgentError] {
  if context.messages.length() == 0 {
    return Err(ContinueWithoutMessages)
  }
  guard last_message(context.messages) is Some(last) else {
    return Err(ContinueWithoutMessages)
  }
  if last is @ai.Message::Assistant(_) {
    return Err(ContinueFromAssistant)
  }
  let new_messages : Array[@ai.Message] = []
  let current_context : AgentContext = {
    system_prompt: context.system_prompt,
    messages: context.messages.copy(),
    tools: context.tools.copy(),
  }
  emit(AgentStart)
  emit(TurnStart)
  match run_loop(current_context, new_messages, config, emit) {
    Ok(_) => Ok(new_messages)
    Err(error) => Err(error)
  }
}

fn run_loop(
  current_context : AgentContext,
  new_messages : Array[@ai.Message],
  config : AgentLoopConfig,
  emit : (AgentEvent) -> Unit
) -> Result[Unit, AgentError] {
  let mut first_turn = true
  let mut pending_messages = drain_message_source(config.get_steering_messages)
  while true {
    let mut has_more_tool_calls = true
    while has_more_tool_calls || pending_messages.length() > 0 {
      if first_turn {
        first_turn = false
      } else {
        emit(TurnStart)
      }
      if pending_messages.length() > 0 {
        for message in pending_messages {
          emit(MessageStart(message))
          emit(MessageEnd(message))
          current_context.messages.push(message)
          new_messages.push(message)
        }
        pending_messages = []
      }
      let assistant_message = match stream_assistant_response(current_context, config, emit) {
        Ok(message) => message
        Err(error) => return Err(error)
      }
      new_messages.push(@ai.Message::Assistant(assistant_message))
      if assistant_message.stop_reason == @ai.StopReason::Error ||
        assistant_message.stop_reason == @ai.StopReason::Aborted {
        emit(TurnEnd({ message: assistant_message, tool_results: [] }))
        emit(AgentEnd(new_messages.copy()))
        return Ok(())
      }
      let tool_calls = extract_tool_calls(assistant_message)
      has_more_tool_calls = tool_calls.length() > 0
      let tool_results = match execute_tool_calls(current_context, assistant_message, config, emit) {
        Ok(results) => results
        Err(error) => return Err(error)
      }
      for result in tool_results {
        current_context.messages.push(@ai.Message::ToolResult(result))
        new_messages.push(@ai.Message::ToolResult(result))
      }
      emit(TurnEnd({ message: assistant_message, tool_results }))
      pending_messages = drain_message_source(config.get_steering_messages)
    }
    let follow_up_messages = drain_message_source(config.get_follow_up_messages)
    if follow_up_messages.length() == 0 {
      break
    }
    pending_messages = follow_up_messages
  }
  emit(AgentEnd(new_messages.copy()))
  Ok(())
}

fn stream_assistant_response(
  context : AgentContext,
  config : AgentLoopConfig,
  emit : (AgentEvent) -> Unit
) -> Result[@ai.AssistantMessage, AgentError] {
  let mut transformed_messages = context.messages.copy()
  match config.transform_context {
    Some(transform) => transformed_messages = transform(transformed_messages)
    None => ()
  }
  let mut llm_messages = transformed_messages.copy()
  match config.convert_to_llm {
    Some(convert) => llm_messages = convert(llm_messages)
    None => ()
  }
  let llm_context : @ai.Context = {
    system_prompt: Some(context.system_prompt),
    messages: llm_messages,
    tools: context.tools.map(tool_to_ai_tool),
  }
  let partial_message : Ref[@ai.AssistantMessage?] = Ref::new(None)
  let final_message : Ref[@ai.AssistantMessage?] = Ref::new(None)
  let added_partial : Ref[Bool] = Ref::new(false)
  let stream_result = run_stream_fn(
    config,
    llm_context,
    @ai.EventHandler(fn(event) {
      match event {
        @ai.AssistantMessageEvent::Start(message) => {
          partial_message.val = Some(message)
          added_partial.val = true
          context.messages.push(@ai.Message::Assistant(message))
          emit(MessageStart(@ai.Message::Assistant(message)))
        }
        @ai.AssistantMessageEvent::TextStart(index) => {
          partial_message.val = partial_message_update(
            partial_message.val,
            index,
            @ai.ContentBlock::Text(""),
          )
          emit_partial_update(context, partial_message.val, event, emit)
        }
        @ai.AssistantMessageEvent::TextDelta(index, delta) => {
          partial_message.val = partial_message_append_text(partial_message.val, index, delta, false)
          emit_partial_update(context, partial_message.val, event, emit)
        }
        @ai.AssistantMessageEvent::TextEnd(index, text) => {
          partial_message.val = partial_message_update(
            partial_message.val,
            index,
            @ai.ContentBlock::Text(text),
          )
          emit_partial_update(context, partial_message.val, event, emit)
        }
        @ai.AssistantMessageEvent::ThinkingStart(index) => {
          partial_message.val = partial_message_update(
            partial_message.val,
            index,
            @ai.ContentBlock::Thinking(""),
          )
          emit_partial_update(context, partial_message.val, event, emit)
        }
        @ai.AssistantMessageEvent::ThinkingDelta(index, delta) => {
          partial_message.val = partial_message_append_text(partial_message.val, index, delta, true)
          emit_partial_update(context, partial_message.val, event, emit)
        }
        @ai.AssistantMessageEvent::ThinkingEnd(index, text) => {
          partial_message.val = partial_message_update(
            partial_message.val,
            index,
            @ai.ContentBlock::Thinking(text),
          )
          emit_partial_update(context, partial_message.val, event, emit)
        }
        @ai.AssistantMessageEvent::ToolCallStart(index, tool_call) => {
          partial_message.val = partial_message_update(
            partial_message.val,
            index,
            @ai.ContentBlock::ToolCall(tool_call),
          )
          emit_partial_update(context, partial_message.val, event, emit)
        }
        @ai.AssistantMessageEvent::ToolCallDelta(_, _) => {
          emit_partial_update(context, partial_message.val, event, emit)
        }
        @ai.AssistantMessageEvent::ToolCallEnd(index, tool_call) => {
          partial_message.val = partial_message_update(
            partial_message.val,
            index,
            @ai.ContentBlock::ToolCall(tool_call),
          )
          emit_partial_update(context, partial_message.val, event, emit)
        }
        @ai.AssistantMessageEvent::Done(_, message) |
        @ai.AssistantMessageEvent::Error(_, message) => {
          final_message.val = Some(message)
          if added_partial.val {
            replace_last_message(context.messages, @ai.Message::Assistant(message))
          } else {
            context.messages.push(@ai.Message::Assistant(message))
            emit(MessageStart(@ai.Message::Assistant(message)))
          }
          emit(MessageEnd(@ai.Message::Assistant(message)))
        }
      }
    }),
  )
  match stream_result {
    Err(error) => Err(error)
    Ok(_) =>
      match final_message.val {
        Some(message) => Ok(message)
        None => Err(StreamFailed("stream ended without terminal message"))
      }
  }
}

fn execute_tool_calls(
  current_context : AgentContext,
  assistant_message : @ai.AssistantMessage,
  config : AgentLoopConfig,
  emit : (AgentEvent) -> Unit
) -> Result[Array[@ai.ToolResultMessage], AgentError] {
  let tool_calls = extract_tool_calls(assistant_message)
  match config.tool_execution {
    Sequential => execute_tool_calls_sequential(current_context, assistant_message, tool_calls, config, emit)
    Parallel => execute_tool_calls_parallel(current_context, assistant_message, tool_calls, config, emit)
  }
}

fn execute_tool_calls_sequential(
  current_context : AgentContext,
  assistant_message : @ai.AssistantMessage,
  tool_calls : Array[@ai.ToolCall],
  config : AgentLoopConfig,
  emit : (AgentEvent) -> Unit
) -> Result[Array[@ai.ToolResultMessage], AgentError] {
  let results : Array[@ai.ToolResultMessage] = []
  for tool_call in tool_calls {
    emit(ToolExecutionStart({
      tool_call_id: tool_call.id,
      tool_name: tool_call.name,
      args: tool_call.arguments,
    }))
    match prepare_tool_call(current_context, assistant_message, tool_call, config) {
      Prepared(prepared) => {
        let executed = execute_prepared_tool_call(prepared, emit)
        results.push(finalize_executed_tool_call(
          current_context,
          assistant_message,
          prepared,
          executed,
          config,
          emit,
        ))
      }
      Immediate(outcome) => results.push(emit_tool_call_outcome(tool_call, outcome.result, outcome.is_error, emit))
    }
  }
  Ok(results)
}

fn execute_tool_calls_parallel(
  current_context : AgentContext,
  assistant_message : @ai.AssistantMessage,
  tool_calls : Array[@ai.ToolCall],
  config : AgentLoopConfig,
  emit : (AgentEvent) -> Unit
) -> Result[Array[@ai.ToolResultMessage], AgentError] {
  let results : Array[@ai.ToolResultMessage] = []
  let runnable_calls : Array[PreparedToolCall] = []
  for tool_call in tool_calls {
    emit(ToolExecutionStart({
      tool_call_id: tool_call.id,
      tool_name: tool_call.name,
      args: tool_call.arguments,
    }))
    match prepare_tool_call(current_context, assistant_message, tool_call, config) {
      Prepared(prepared) => runnable_calls.push(prepared)
      Immediate(outcome) => results.push(emit_tool_call_outcome(tool_call, outcome.result, outcome.is_error, emit))
    }
  }
  // MoonBit Native 现阶段仍以同步执行为主；这里保留“先预检再执行”的顺序，
  // 让 API 形状和 pi-mono 对齐，后续可替换成真正并发执行。
  for prepared in runnable_calls {
    let executed = execute_prepared_tool_call(prepared, emit)
    results.push(finalize_executed_tool_call(
      current_context,
      assistant_message,
      prepared,
      executed,
      config,
      emit,
    ))
  }
  Ok(results)
}

priv enum PreparedToolCallState {
  Prepared(PreparedToolCall)
  Immediate(ImmediateToolCallOutcome)
}

fn prepare_tool_call(
  current_context : AgentContext,
  assistant_message : @ai.AssistantMessage,
  tool_call : @ai.ToolCall,
  config : AgentLoopConfig
) -> PreparedToolCallState {
  match find_tool(current_context.tools, tool_call.name) {
    None => Immediate({
      result: create_error_tool_result("Tool " + tool_call.name + " not found"),
      is_error: true,
    })
    Some(tool) => {
      let prepared_args = match tool.prepare_arguments {
        Some(prepare_arguments) =>
          match prepare_arguments(tool_call.arguments) {
            Ok(args) => args
            Err(message) => return Immediate({ result: create_error_tool_result(message), is_error: true })
          }
        None => tool_call.arguments
      }
      match tool.validate_arguments {
        Some(validate_arguments) =>
          match validate_arguments(prepared_args) {
            Ok(_) => ()
            Err(message) => return Immediate({ result: create_error_tool_result(message), is_error: true })
          }
        None => ()
      }
      match config.before_tool_call {
        Some(before_tool_call) =>
          match before_tool_call({
            assistant_message,
            tool_call,
            args: prepared_args,
            context: clone_agent_context(current_context),
          }) {
            Some(result) if result.block =>
              Immediate({
                result: create_error_tool_result(before_tool_call_reason(result)),
                is_error: true,
              })
            _ => Prepared({ tool_call, tool, args: prepared_args })
          }
        None => Prepared({ tool_call, tool, args: prepared_args })
      }
    }
  }
}

fn execute_prepared_tool_call(
  prepared : PreparedToolCall,
  emit : (AgentEvent) -> Unit
) -> ExecutedToolCallOutcome {
  match (prepared.tool.execute)(
    prepared.tool_call.id,
    prepared.args,
    AgentToolUpdateHandler(fn(partial_result) {
      emit(ToolExecutionUpdate({
        tool_call_id: prepared.tool_call.id,
        tool_name: prepared.tool_call.name,
        args: prepared.args,
        partial_result,
      }))
    }),
  ) {
    Ok(result) => { result, is_error: false }
    Err(message) => { result: create_error_tool_result(message), is_error: true }
  }
}

fn finalize_executed_tool_call(
  current_context : AgentContext,
  assistant_message : @ai.AssistantMessage,
  prepared : PreparedToolCall,
  executed : ExecutedToolCallOutcome,
  config : AgentLoopConfig,
  emit : (AgentEvent) -> Unit
) -> @ai.ToolResultMessage {
  let mut result = executed.result
  let mut is_error = executed.is_error
  match config.after_tool_call {
    Some(after_tool_call) =>
      match after_tool_call({
        assistant_message,
        tool_call: prepared.tool_call,
        args: prepared.args,
        result,
        is_error,
        context: clone_agent_context(current_context),
      }) {
        Some(after_result) => {
          result = {
            content: match after_result.content {
              Some(content) => content
              None => result.content
            },
            details: match after_result.details {
              Some(details) => details
              None => result.details
            },
          }
          is_error = match after_result.is_error {
            Some(next) => next
            None => is_error
          }
        }
        None => ()
      }
    None => ()
  }
  emit_tool_call_outcome(prepared.tool_call, result, is_error, emit)
}

fn emit_tool_call_outcome(
  tool_call : @ai.ToolCall,
  result : AgentToolResult,
  is_error : Bool,
  emit : (AgentEvent) -> Unit
) -> @ai.ToolResultMessage {
  emit(ToolExecutionEnd({
    tool_call_id: tool_call.id,
    tool_name: tool_call.name,
    result,
    is_error,
  }))
  let tool_result_message : @ai.ToolResultMessage = {
    content: result.content,
    tool_call_id: tool_call.id,
    tool_name: tool_call.name,
    error: is_error,
  }
  emit(MessageStart(@ai.Message::ToolResult(tool_result_message)))
  emit(MessageEnd(@ai.Message::ToolResult(tool_result_message)))
  tool_result_message
}

fn emit_partial_update(
  context : AgentContext,
  partial_message : @ai.AssistantMessage?,
  event : @ai.AssistantMessageEvent,
  emit : (AgentEvent) -> Unit
) -> Unit {
  match partial_message {
    Some(message) => {
      replace_last_message(context.messages, @ai.Message::Assistant(message))
      emit(MessageUpdate({ message: @ai.Message::Assistant(message), assistant_event: event }))
    }
    None => ()
  }
}

fn partial_message_update(
  partial_message : @ai.AssistantMessage?,
  index : Int,
  block : @ai.ContentBlock
) -> @ai.AssistantMessage? {
  match partial_message {
    None => None
    Some(message) => {
      let next_content = ensure_content_index(message.content.copy(), index)
      next_content[index] = block
      Some({
        content: next_content,
        api: message.api,
        provider: message.provider,
        model: message.model,
        usage: message.usage,
        stop_reason: message.stop_reason,
        error_message: message.error_message,
        timestamp: message.timestamp,
      })
    }
  }
}

fn partial_message_append_text(
  partial_message : @ai.AssistantMessage?,
  index : Int,
  delta : String,
  thinking : Bool
) -> @ai.AssistantMessage? {
  match partial_message {
    None => None
    Some(message) => {
      let next_content = ensure_content_index(message.content.copy(), index)
      let next_block = match next_content[index] {
        @ai.ContentBlock::Text(text) if !thinking => @ai.ContentBlock::Text(text + delta)
        @ai.ContentBlock::Thinking(text) if thinking => @ai.ContentBlock::Thinking(text + delta)
        _ =>
          if thinking {
            @ai.ContentBlock::Thinking(delta)
          } else {
            @ai.ContentBlock::Text(delta)
          }
      }
      next_content[index] = next_block
      Some({
        content: next_content,
        api: message.api,
        provider: message.provider,
        model: message.model,
        usage: message.usage,
        stop_reason: message.stop_reason,
        error_message: message.error_message,
        timestamp: message.timestamp,
      })
    }
  }
}

fn ensure_content_index(content : Array[@ai.ContentBlock], index : Int) -> Array[@ai.ContentBlock] {
  while content.length() <= index {
    content.push(@ai.ContentBlock::Text(""))
  }
  content
}

fn run_stream_fn(
  config : AgentLoopConfig,
  context : @ai.Context,
  handler : @ai.EventHandler
) -> Result[Unit, AgentError] {
  match config.stream_fn {
    Some(stream_fn) =>
      match stream_fn.0(config.model, context, config.options, handler) {
        Ok(_) => Ok(())
        Err(message) => Err(StreamFailed(message))
      }
    None =>
      try {
        @ai.stream(config.model, context, config.options, handler)
        Ok(())
      } catch {
        @ai.StreamError(message) => Err(StreamFailed(message))
      }
  }
}

fn extract_tool_calls(message : @ai.AssistantMessage) -> Array[@ai.ToolCall] {
  let tool_calls : Array[@ai.ToolCall] = []
  for block in message.content {
    match block {
      @ai.ContentBlock::ToolCall(tool_call) => tool_calls.push(tool_call)
      _ => ()
    }
  }
  tool_calls
}

fn tool_to_ai_tool(tool : AgentTool) -> @ai.Tool {
  {
    name: tool.name,
    description: tool.description,
    parameters: tool.parameters,
  }
}

fn find_tool(tools : Array[AgentTool], name : String) -> AgentTool? {
  for tool in tools {
    if tool.name == name {
      return Some(tool)
    }
  }
  None
}

fn drain_message_source(source : (() -> Array[@ai.Message])?) -> Array[@ai.Message] {
  match source {
    Some(f) => f()
    None => []
  }
}

fn replace_last_message(messages : Array[@ai.Message], message : @ai.Message) -> Unit {
  if messages.length() == 0 {
    messages.push(message)
  } else {
    messages[messages.length() - 1] = message
  }
}

fn last_message(messages : Array[@ai.Message]) -> @ai.Message? {
  if messages.length() == 0 {
    None
  } else {
    Some(messages[messages.length() - 1])
  }
}

fn create_error_tool_result(message : String) -> AgentToolResult {
  {
    content: [@ai.ContentBlock::Text(message)],
    details: empty_json_object(),
  }
}

fn before_tool_call_reason(result : BeforeToolCallResult) -> String {
  match result.reason {
    Some(reason) if reason.length() > 0 => reason
    _ => "Tool execution was blocked"
  }
}

fn clone_agent_context(context : AgentContext) -> AgentContext {
  {
    system_prompt: context.system_prompt,
    messages: context.messages.copy(),
    tools: context.tools.copy(),
  }
}
