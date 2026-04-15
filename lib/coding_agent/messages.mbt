pub let compaction_summary_prefix : String =
  "The conversation history before this point was compacted into the following summary:\n\n<summary>\n"

pub let compaction_summary_suffix : String = "\n</summary>"

pub let branch_summary_prefix : String =
  "The following is a summary of a branch that this conversation came back from:\n\n<summary>\n"

pub let branch_summary_suffix : String = "\n</summary>"

///| 把 bash 执行记录变成可注入 LLM 的文本。
pub fn bash_execution_to_text(message : BashExecutionMessage) -> String {
  let mut text = "Ran `\{message.command}`\n"
  if message.output.length() > 0 {
    text = text + "```\n" + message.output + "\n```"
  } else {
    text = text + "(no output)"
  }
  if message.cancelled {
    text = text + "\n\n(command cancelled)"
  } else {
    match message.exit_code {
      Some(code) if code != 0 => text = text + "\n\nCommand exited with code \{code}"
      _ => ()
    }
  }
  if message.truncated {
    match message.full_output_path {
      Some(path) =>
        text = text + "\n\n[Output truncated. Full output: " + path + "]"
      None => text = text + "\n\n[Output truncated]"
    }
  }
  text
}

///| 把自定义上下文消息转换成标准 LLM user message。
pub fn context_message_to_llm(message : ContextMessage) -> @ai.Message {
  match message {
    Custom(custom_message) =>
      @ai.Message::User({ content: custom_message.content.copy() })
    BashExecution(bash_message) =>
      @ai.Message::User({ content: [@ai.ContentBlock::Text(bash_execution_to_text(bash_message))] })
  }
}

///| 把 compaction entry 转成 user message。
pub fn compaction_entry_to_llm(entry : CompactionEntry) -> @ai.Message {
  @ai.Message::User({
    content: [@ai.ContentBlock::Text(
      compaction_summary_prefix + entry.summary + compaction_summary_suffix,
    )],
  })
}

///| 把 branch summary entry 转成 user message。
pub fn branch_summary_entry_to_llm(entry : BranchSummaryEntry) -> @ai.Message {
  @ai.Message::User({
    content: [@ai.ContentBlock::Text(
      branch_summary_prefix + entry.summary + branch_summary_suffix,
    )],
  })
}
