fn host_wait_oauth_callback(
  _port : Int,
  _expected_state : String,
  _timeout_ms : Int
) -> Result[(String, String), String] {
  Err("OAuth callback server is not implemented for wasm target")
}

fn host_post_form(_url : String, _form_body : String) -> Result[(Int, String), String] {
  Err("HTTP POST is not implemented for wasm target")
}

fn host_get_bearer(_url : String, _bearer : String) -> Result[(Int, String), String] {
  Err("HTTP GET is not implemented for wasm target")
}

fn host_open_browser(_url : String) -> Unit {
  ()
}

fn host_wait_cli_callback(
  _port : Int,
  _expected_state : String,
  _timeout_ms : Int
) -> Result[(String, String?, String), String] {
  Err("CLI callback server is not implemented for wasm target")
}

fn host_get(_url : String) -> Result[(Int, String), String] {
  Err("HTTP GET is not implemented for wasm target")
}

fn host_post_json_bearer(_url : String, _body : String, _bearer : String) -> Result[(Int, String), String] {
  Err("HTTP POST JSON is not implemented for wasm target")
}

fn host_delete_bearer(_url : String, _bearer : String) -> Result[(Int, String), String] {
  Err("HTTP DELETE is not implemented for wasm target")
}
