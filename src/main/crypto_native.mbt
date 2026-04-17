fn host_random_state() -> String {
  "native-state-placeholder"
}

fn host_generate_pkce() -> @ai.PkceChallenge {
  @ai.pkce_challenge_s256(
    "native-verifier-placeholder-do-not-use",
    "native-challenge-placeholder",
  )
}
