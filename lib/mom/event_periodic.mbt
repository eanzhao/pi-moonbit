pub fn MomPeriodicRegistry::new() -> MomPeriodicRegistry {
  { entries: [] }
}

pub fn MomPeriodicRegistry::list_entries(
  self : MomPeriodicRegistry
) -> Array[MomRegisteredPeriodic] {
  sort_registered_periodics(self.entries.copy())
}

pub fn MomPeriodicRegistry::apply_sync(
  self : MomPeriodicRegistry,
  sync : MomEventHostSync
) -> Unit {
  for removed in sync.removed_periodics {
    ignore(self.remove(removed.filename))
  }
  for added in sync.added_periodics {
    self.register(added)
  }
}

pub fn MomPeriodicRegistry::register(
  self : MomPeriodicRegistry,
  entry : MomRegisteredPeriodic
) -> Unit {
  for i in 0..<self.entries.length() {
    if self.entries[i].filename == entry.filename {
      self.entries[i] = entry
      return
    }
  }
  self.entries.push(entry)
}

pub fn MomPeriodicRegistry::remove(
  self : MomPeriodicRegistry,
  filename : String
) -> Bool {
  let retained : Array[MomRegisteredPeriodic] = []
  let mut removed = false
  for item in self.entries {
    if item.filename == filename {
      removed = true
    } else {
      retained.push(item)
    }
  }
  self.entries = retained
  removed
}

fn sort_registered_periodics(
  items : Array[MomRegisteredPeriodic]
) -> Array[MomRegisteredPeriodic] {
  let mut remaining = items.copy()
  let sorted : Array[MomRegisteredPeriodic] = []
  while remaining.length() > 0 {
    let earliest_index = earliest_registered_periodic_index(remaining)
    sorted.push(remaining[earliest_index])
    remaining = filter_registered_periodics_by_index(remaining, earliest_index)
  }
  sorted
}

fn earliest_registered_periodic_index(items : Array[MomRegisteredPeriodic]) -> Int {
  let mut earliest_index = 0
  for i in 1..<items.length() {
    if registered_periodic_sort_key(items[i]) < registered_periodic_sort_key(items[earliest_index]) {
      earliest_index = i
    }
  }
  earliest_index
}

fn registered_periodic_sort_key(item : MomRegisteredPeriodic) -> String {
  item.filename + "\n" + item.event.schedule
}

fn filter_registered_periodics_by_index(
  items : Array[MomRegisteredPeriodic],
  index : Int
) -> Array[MomRegisteredPeriodic] {
  let filtered : Array[MomRegisteredPeriodic] = []
  for i in 0..<items.length() {
    if i != index {
      filtered.push(items[i])
    }
  }
  filtered
}
