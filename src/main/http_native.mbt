fn host_anthropic_stream(
  _model : @ai.Model,
  _context : @ai.Context,
  _options : @ai.StreamOptions,
  _handler : @ai.EventHandler
) -> Unit!@ai.StreamError {
  raise @ai.StreamError("Anthropic streaming is not implemented for native target yet")
}

fn host_openai_stream(
  _model : @ai.Model,
  _context : @ai.Context,
  _options : @ai.StreamOptions,
  _handler : @ai.EventHandler
) -> Unit!@ai.StreamError {
  raise @ai.StreamError("OpenAI streaming is not implemented for native target yet")
}

fn host_env_var(_name : String) -> String? {
  None
}
