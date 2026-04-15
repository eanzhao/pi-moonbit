///|
pub suberror StreamError {
  StreamError(String)
} derive(Show)

///|
/// Callback that receives streaming events from a provider.
pub(all) struct EventHandler((AssistantMessageEvent) -> Unit)

///|
/// A registered stream function for an API.
/// Takes (model, context, options, event_handler) and streams events.
struct ProviderEntry {
  api : ApiId
  stream_fn : (Model, Context, StreamOptions, EventHandler) -> Unit!StreamError
}

///|
let providers : Array[ProviderEntry] = []

///|
/// Register a stream function for the given API.
pub fn register_provider(
  api : ApiId,
  f : (Model, Context, StreamOptions, EventHandler) -> Unit!StreamError
) -> Unit {
  for i = 0; i < providers.length(); i = i + 1 {
    if providers[i].api == api {
      providers[i] = { api, stream_fn: f }
      return
    }
  }
  providers.push({ api, stream_fn: f })
}

///|
/// Look up the registered stream function for an API.
pub fn get_provider(
  api : ApiId
) -> ((Model, Context, StreamOptions, EventHandler) -> Unit!StreamError)? {
  for i = 0; i < providers.length(); i = i + 1 {
    if providers[i].api == api {
      return Some(providers[i].stream_fn)
    }
  }
  None
}

///|
/// Remove all registered providers.
pub fn clear_providers() -> Unit {
  providers.clear()
}

///|
/// Stream a response from the LLM registered for the model's API.
pub fn stream(
  model : Model,
  context : Context,
  options : StreamOptions,
  handler : EventHandler
) -> Unit!StreamError {
  match get_provider(model.api) {
    Some(f) => f!(model, context, options, handler)
    None => raise StreamError("no provider registered for API: " + model.api.0)
  }
}

///|
/// Send a request and collect the full response (non-streaming convenience).
pub fn complete(
  model : Model,
  context : Context,
  options : StreamOptions
) -> AssistantMessage!StreamError {
  let result : Ref[AssistantMessage?] = Ref::new(None)
  stream!(model, context, options, fn(event) {
    match event {
      Done(_, msg) | Error(_, msg) => result.val = Some(msg)
      _ => ()
    }
  })
  match result.val {
    Some(msg) => msg
    None => raise StreamError("stream ended without a terminal event")
  }
}
