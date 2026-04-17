///| Artifact 类型定义（12 种 pi-mono artifact 支持）。
///
/// Artifact 是对话中产出的可渲染文档（HTML/Markdown/Code/Image 等）。
/// 实际的渲染在浏览器 iframe 中完成，此模块定义数据模型。

///| Artifact 类型。
pub(all) enum ArtifactType {
  Html
  Svg
  Markdown
  Code(String)  // language
  Image(String)  // mime type
  Text
  Pdf
  Excel
  Docx
  Csv
  Json
  Generic(String)  // custom mime
} derive(Show)

///| Artifact 数据。
pub(all) struct Artifact {
  id : String
  title : String
  artifact_type : ArtifactType
  content : String  // 文本内容或 base64 数据
  language : String?  // 用于 Code
  mime_type : String
  size : Int
  created_at : String
  updated_at : String?
}

///| 按扩展名/内容推断 artifact 类型。
pub fn detect_artifact_type(filename : String, mime : String) -> ArtifactType {
  let lower = filename.to_lower()
  if lower.has_suffix(".html") || lower.has_suffix(".htm") { return Html }
  if lower.has_suffix(".svg") { return Svg }
  if lower.has_suffix(".md") || lower.has_suffix(".markdown") { return Markdown }
  if lower.has_suffix(".pdf") { return Pdf }
  if lower.has_suffix(".xlsx") || lower.has_suffix(".xls") { return Excel }
  if lower.has_suffix(".docx") || lower.has_suffix(".doc") { return Docx }
  if lower.has_suffix(".csv") { return Csv }
  if lower.has_suffix(".json") { return Json }
  if lower.has_suffix(".txt") { return Text }
  // Code by extension (checked before generic mime prefixes)
  let code_langs : Array[(String, String)] = [
    (".js", "javascript"), (".ts", "typescript"),
    (".py", "python"), (".rs", "rust"), (".go", "go"),
    (".cpp", "cpp"), (".c", "c"), (".h", "c"),
    (".java", "java"), (".mbt", "moonbit"),
    (".sh", "bash"), (".rb", "ruby"), (".swift", "swift"),
  ]
  for pair in code_langs {
    let (ext, lang) = pair
    if lower.has_suffix(ext) { return Code(lang) }
  }
  if mime.has_prefix("image/") { return Image(mime) }
  if mime.has_prefix("text/") { return Text }
  Generic(mime)
}

///| Artifact pill（列表中的指示器）。
pub(all) struct ArtifactPill {
  artifact_id : String
  title : String
  icon : String  // 用于 UI 显示的 emoji/icon
  color_class : String
}

///| 为 artifact 生成 pill。
pub fn artifact_pill(artifact : Artifact) -> ArtifactPill {
  let (icon, color) = match artifact.artifact_type {
    Html => ("🌐", "html")
    Svg => ("🎨", "svg")
    Markdown => ("📝", "markdown")
    Code(_) => ("📄", "code")
    Image(_) => ("🖼️", "image")
    Text => ("📄", "text")
    Pdf => ("📕", "pdf")
    Excel => ("📊", "excel")
    Docx => ("📘", "docx")
    Csv => ("📈", "csv")
    Json => ("{}", "json")
    Generic(_) => ("📎", "generic")
  }
  { artifact_id: artifact.id, title: artifact.title, icon, color_class: color }
}

///| Artifact 渲染配置（sandbox 要求）。
pub(all) struct ArtifactRenderConfig {
  allow_scripts : Bool
  allow_forms : Bool
  allow_popups : Bool
  sandbox_flags : Array[String]
}

///| 安全的默认 sandbox 配置。
pub fn safe_sandbox_config(artifact_type : ArtifactType) -> ArtifactRenderConfig {
  match artifact_type {
    Html | Svg => {
      allow_scripts: true,
      allow_forms: false,
      allow_popups: false,
      sandbox_flags: ["allow-scripts"],
    }
    _ => {
      allow_scripts: false,
      allow_forms: false,
      allow_popups: false,
      sandbox_flags: [],
    }
  }
}

///| Artifact 注册表（存储会话中所有 artifact）。
pub(all) struct ArtifactRegistry {
  mut artifacts : Array[Artifact]
}

pub fn ArtifactRegistry::new() -> ArtifactRegistry {
  { artifacts: [] }
}

pub fn ArtifactRegistry::add(self : ArtifactRegistry, artifact : Artifact) -> Unit {
  for i = 0; i < self.artifacts.length(); i = i + 1 {
    if self.artifacts[i].id == artifact.id {
      self.artifacts[i] = artifact
      return
    }
  }
  self.artifacts.push(artifact)
}

pub fn ArtifactRegistry::get(self : ArtifactRegistry, id : String) -> Artifact? {
  for a in self.artifacts {
    if a.id == id { return Some(a) }
  }
  None
}

pub fn ArtifactRegistry::remove(self : ArtifactRegistry, id : String) -> Unit {
  let retained : Array[Artifact] = []
  for a in self.artifacts {
    if a.id != id { retained.push(a) }
  }
  self.artifacts = retained
}

pub fn ArtifactRegistry::list(self : ArtifactRegistry) -> Array[Artifact] {
  self.artifacts.copy()
}
