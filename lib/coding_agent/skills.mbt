pub(all) struct Skill {
  name : String
  description : String
  prompt_template : String
  source : String
}

pub(all) struct SkillRegistry {
  mut skills : Array[Skill]
}

pub fn SkillRegistry::new() -> SkillRegistry {
  { skills: [] }
}

pub fn SkillRegistry::register(self : SkillRegistry, skill : Skill) -> Unit {
  self.skills.push(skill)
}

pub fn SkillRegistry::get(self : SkillRegistry, name : String) -> Skill? {
  for skill in self.skills {
    if skill.name == name {
      return Some(skill)
    }
  }
  None
}

pub fn SkillRegistry::list(self : SkillRegistry) -> Array[Skill] {
  self.skills.copy()
}

pub fn SkillRegistry::invoke(self : SkillRegistry, name : String, args : String) -> String? {
  match self.get(name) {
    Some(skill) => Some(skill.prompt_template.replace(old="{args}", new=args))
    None => None
  }
}
