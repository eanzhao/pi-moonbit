fn host_random_state() -> String {
  "wasm-state-placeholder"
}

fn host_generate_pkce() -> @ai.PkceChallenge {
  @ai.pkce_challenge_s256(
    "wasm-verifier-placeholder-do-not-use",
    "wasm-challenge-placeholder",
  )
}
