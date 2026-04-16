pub fn subsequence_score(query : String, text : String) -> Double {
  let normalized_query = query.to_lower().replace_all(old=" ", new="")
  if normalized_query.length() == 0 {
    return 0.0
  }

  let normalized_text = text.to_lower()
  let mut query_index = 0
  let mut text_index = 0
  let mut gaps = 0
  let mut last_match_index = -1

  while query_index < normalized_query.length() && text_index < normalized_text.length() {
    if normalized_query[query_index:query_index + 1] == normalized_text[text_index:text_index + 1] {
      if last_match_index >= 0 {
        gaps = gaps + text_index - last_match_index - 1
      }
      last_match_index = text_index
      query_index = query_index + 1
    }
    text_index = text_index + 1
  }

  if query_index < normalized_query.length() {
    0.0
  } else {
    normalized_query.length().to_double() / (normalized_query.length() + gaps).to_double()
  }
}

pub fn filter_selectable_models(
  models : Array[SelectableModel],
  search_query? : String = "",
  filter_reasoning? : Bool = false,
  filter_vision? : Bool = false,
  current_model? : @ai.Model? = None,
  allowed_providers? : Array[String]? = None
) -> Array[SelectableModel] {
  let filtered : Array[SelectableModel] = []
  for entry in models {
    if !model_selector_provider_allowed(entry.provider, allowed_providers) {
      continue
    }
    if filter_reasoning && !entry.model.reasoning {
      continue
    }
    if filter_vision && !model_selector_supports_vision(entry.model) {
      continue
    }
    filtered.push(entry)
  }

  if search_query.trim().length() > 0 {
    return model_selector_sort_by_search_score(filtered, search_query)
  }
  model_selector_sort_default(filtered, current_model)
}

fn model_selector_supports_vision(model : @ai.Model) -> Bool {
  for modality in model.input_modalities {
    if modality == @ai.InputModality::Image {
      return true
    }
  }
  false
}

fn model_selector_provider_allowed(
  provider : String,
  allowed_providers : Array[String]?
) -> Bool {
  match allowed_providers {
    Some(allowed) =>
      for item in allowed {
        if item == provider {
          return true
        }
      }
    None => return true
  }
  false
}

fn model_selector_sort_by_search_score(
  models : Array[SelectableModel],
  search_query : String
) -> Array[SelectableModel] {
  let mut remaining = models.copy()
  let sorted : Array[SelectableModel] = []
  while remaining.length() > 0 {
    let best_index = model_selector_pick_best_search_index(remaining, search_query)
    let score = subsequence_score(search_query, model_selector_search_text(remaining[best_index]))
    if score <= 0.0 {
      return sorted
    }
    sorted.push(remaining[best_index])
    remaining = model_selector_remove_at(remaining, best_index)
  }
  sorted
}

fn model_selector_pick_best_search_index(
  models : Array[SelectableModel],
  search_query : String
) -> Int {
  let mut selected = 0
  let mut selected_score = subsequence_score(search_query, model_selector_search_text(models[0]))
  for i in 1..<models.length() {
    let candidate_score = subsequence_score(search_query, model_selector_search_text(models[i]))
    if candidate_score > selected_score {
      selected = i
      selected_score = candidate_score
    }
  }
  selected
}

fn model_selector_sort_default(
  models : Array[SelectableModel],
  current_model : @ai.Model?
) -> Array[SelectableModel] {
  let mut remaining = models.copy()
  let sorted : Array[SelectableModel] = []
  while remaining.length() > 0 {
    let next_index = model_selector_pick_default_index(remaining, current_model)
    sorted.push(remaining[next_index])
    remaining = model_selector_remove_at(remaining, next_index)
  }
  sorted
}

fn model_selector_pick_default_index(
  models : Array[SelectableModel],
  current_model : @ai.Model?
) -> Int {
  let mut selected = 0
  for i in 1..<models.length() {
    if model_selector_compare_default(models[i], models[selected], current_model) < 0 {
      selected = i
    }
  }
  selected
}

fn model_selector_compare_default(
  left : SelectableModel,
  right : SelectableModel,
  current_model : @ai.Model?
) -> Int {
  let left_is_current = match current_model {
    Some(model) => @ai.models_are_equal(left.model, model)
    None => false
  }
  let right_is_current = match current_model {
    Some(model) => @ai.models_are_equal(right.model, model)
    None => false
  }

  if left_is_current && !right_is_current {
    return -1
  }
  if !left_is_current && right_is_current {
    return 1
  }
  if left.provider != right.provider {
    return left.provider.compare(right.provider)
  }
  if left.model.name != right.model.name {
    return left.model.name.compare(right.model.name)
  }
  left.model.id.compare(right.model.id)
}

fn model_selector_search_text(model : SelectableModel) -> String {
  model.provider + " " + model.model.id + " " + model.model.name
}

fn model_selector_remove_at(
  models : Array[SelectableModel],
  index : Int
) -> Array[SelectableModel] {
  let retained : Array[SelectableModel] = []
  for i in 0..<models.length() {
    if i != index {
      retained.push(models[i])
    }
  }
  retained
}
