///| MIME 类型检测（按文件扩展名）。

///| 根据扩展名返回 MIME 类型。
pub fn mime_type_for_extension(ext : String) -> String {
  let lower = ext.to_lower()
  match lower {
    // Text
    ".txt" => "text/plain"
    ".md" | ".markdown" => "text/markdown"
    ".html" | ".htm" => "text/html"
    ".css" => "text/css"
    ".csv" => "text/csv"
    ".xml" => "application/xml"
    // Code
    ".js" | ".mjs" => "application/javascript"
    ".ts" => "application/typescript"
    ".json" => "application/json"
    ".jsonl" => "application/x-ndjson"
    ".yaml" | ".yml" => "application/yaml"
    ".toml" => "application/toml"
    ".rs" => "text/x-rust"
    ".py" => "text/x-python"
    ".go" => "text/x-go"
    ".c" | ".h" => "text/x-c"
    ".cpp" | ".hpp" | ".cc" => "text/x-c++"
    ".java" => "text/x-java"
    ".sh" | ".bash" | ".zsh" => "application/x-sh"
    ".mbt" => "text/x-moonbit"
    // Images
    ".jpg" | ".jpeg" => "image/jpeg"
    ".png" => "image/png"
    ".gif" => "image/gif"
    ".webp" => "image/webp"
    ".svg" => "image/svg+xml"
    ".bmp" => "image/bmp"
    // Documents
    ".pdf" => "application/pdf"
    ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    // Archives
    ".zip" => "application/zip"
    ".tar" => "application/x-tar"
    ".gz" => "application/gzip"
    // Audio/Video
    ".mp3" => "audio/mpeg"
    ".wav" => "audio/wav"
    ".mp4" => "video/mp4"
    // Default
    _ => "application/octet-stream"
  }
}

///| 按路径返回 MIME 类型。
pub fn mime_type_for_path(path : String) -> String {
  mime_type_for_extension(extension(path))
}

///| 判断 MIME 类型是否为文本。
pub fn is_text_mime_type(mime : String) -> Bool {
  mime.has_prefix("text/") ||
  mime == "application/json" ||
  mime == "application/xml" ||
  mime == "application/yaml" ||
  mime == "application/toml" ||
  mime == "application/javascript" ||
  mime == "application/typescript" ||
  mime == "application/x-sh" ||
  mime == "application/x-ndjson"
}

///| 判断 MIME 类型是否为图片。
pub fn is_image_mime_type(mime : String) -> Bool {
  mime.has_prefix("image/")
}
