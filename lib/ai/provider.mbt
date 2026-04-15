///| 流式传输过程中的错误。
pub suberror StreamError {
  StreamError(String)
} derive(Show)

///| 事件回调处理器，接收流式传输中产生的事件。
pub(all) struct EventHandler((AssistantMessageEvent) -> Unit)

///| 已注册的供应商流式函数条目，将 API 标识映射到对应的流式处理函数。
struct ProviderEntry {
  api : ApiId
  stream_fn : (Model, Context, StreamOptions, EventHandler) -> Unit!StreamError
}

///| 全局供应商注册表。
let providers : Array[ProviderEntry] = []

///| 为指定 API 注册流式处理函数。
/// 若该 API 已注册，则覆盖原有的处理函数。
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

///| 根据 API 标识查找已注册的流式处理函数。
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

///| 清除所有已注册的供应商（主要用于测试）。
pub fn clear_providers() -> Unit {
  providers.clear()
}

///| 通过模型对应的 API 供应商发起流式请求。
/// 如果该 API 未注册供应商，则抛出 StreamError。
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

///| 非流式便捷接口：发送请求并等待完整响应。
/// 内部通过 stream() 实现，收集终止事件中的最终消息。
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
