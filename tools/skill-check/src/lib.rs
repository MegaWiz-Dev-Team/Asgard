// Asgard AI Platform
// Copyright (C) 2026 MegaCare Dev
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

//! Checks `skills/` against `skills/SPEC.md` and keeps its generated blocks current.
//!
//! The parser here is the contract: a skill this crate accepts is a skill a
//! runtime loader built on [`parse_skill`] will accept.

use serde::Deserialize;
use std::collections::BTreeMap;
use std::fmt;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub const LOCATIONS: [&str; 2] = ["public", "custom"];
pub const MAX_DESCRIPTION: usize = 1024;

const BEGIN: &str = "<!-- skill-check:begin ";
const BEGIN_CLOSE: &str = " -->";
const END: &str = "<!-- skill-check:end -->";
const DEPLOY_SCRIPT: &str = "scripts/k3s-deploy.sh";

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Frontmatter {
    pub name: String,
    pub description: String,
    #[serde(default)]
    pub version: Option<String>,
    #[serde(default)]
    pub author: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub tools: Vec<String>,
    #[serde(default)]
    pub status: Status,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    #[default]
    Active,
    Draft,
    Retired,
}

impl fmt::Display for Status {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Status::Active => "active",
            Status::Draft => "draft",
            Status::Retired => "retired",
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Rule {
    Frontmatter,
    Name,
    Description,
    Location,
    Duplicate,
    Block,
}

impl fmt::Display for Rule {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Rule::Frontmatter => "frontmatter",
            Rule::Name => "name",
            Rule::Description => "description",
            Rule::Location => "location",
            Rule::Duplicate => "duplicate",
            Rule::Block => "block",
        })
    }
}

#[derive(Debug)]
pub struct Finding {
    pub rule: Rule,
    pub path: PathBuf,
    pub detail: String,
}

impl fmt::Display for Finding {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} {}: {}", self.rule, self.path.display(), self.detail)
    }
}

pub struct Skill {
    pub path: PathBuf,
    pub location: String,
    pub front: Frontmatter,
}

/// Splits a SKILL.md into its frontmatter and body. The file must open with a
/// `---` line and close the YAML with the next `---` line.
pub fn parse_skill(text: &str) -> Result<(Frontmatter, &str), String> {
    let rest = text
        .strip_prefix("---\n")
        .ok_or("file does not open with a `---` frontmatter line")?;
    let mut offset = 0;
    for line in rest.split_inclusive('\n') {
        if line.trim_end_matches('\n') == "---" {
            let front = serde_yaml::from_str(&rest[..offset]).map_err(|e| e.to_string())?;
            return Ok((front, &rest[offset + line.len()..]));
        }
        offset += line.len();
    }
    Err("frontmatter has no closing `---` line".into())
}

pub fn is_kebab(name: &str) -> bool {
    !name.is_empty()
        && name.split('-').all(|part| {
            !part.is_empty() && part.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit())
        })
}

pub fn check(root: &Path) -> io::Result<Vec<Finding>> {
    Ok(scan(root, false)?.0)
}

/// Rewrites every stale generated block and returns the files it changed.
/// Run [`check`] afterwards for what a rewrite cannot fix.
pub fn write(root: &Path) -> io::Result<Vec<PathBuf>> {
    Ok(scan(root, true)?.1)
}

fn scan(root: &Path, write: bool) -> io::Result<(Vec<Finding>, Vec<PathBuf>)> {
    let skills_root = root.join("skills");
    if !skills_root.is_dir() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("{} is not a directory", skills_root.display()),
        ));
    }
    let files = walk(&skills_root)?;
    let mut findings = Vec::new();
    let mut skills = Vec::new();

    for rel in files.iter().filter(|p| p.file_name().is_some_and(|n| n == "SKILL.md")) {
        let text = fs::read_to_string(skills_root.join(rel))?;
        if let Some(skill) = check_skill(rel, &text, &mut findings) {
            skills.push(skill);
        }
    }

    let mut seen: BTreeMap<&str, &Path> = BTreeMap::new();
    for skill in &skills {
        if let Some(first) = seen.insert(&skill.front.name, &skill.path) {
            findings.push(Finding {
                rule: Rule::Duplicate,
                path: skill.path.clone(),
                detail: format!("name `{}` is already used by {}", skill.front.name, first.display()),
            });
        }
    }

    let mut changed = Vec::new();
    for rel in files.iter().filter(|p| p.extension().is_some_and(|e| e == "md")) {
        let path = skills_root.join(rel);
        let text = fs::read_to_string(&path)?;
        let fresh = regenerate(&text, root, &skills, rel, &mut findings);
        if fresh != text && write {
            fs::write(&path, fresh)?;
            changed.push(path);
        }
    }

    Ok((findings, changed))
}

fn check_skill(rel: &Path, text: &str, findings: &mut Vec<Finding>) -> Option<Skill> {
    let mut report = |rule, detail: String| {
        findings.push(Finding { rule, path: rel.to_path_buf(), detail });
    };

    let parts: Vec<&str> = rel.iter().filter_map(|c| c.to_str()).collect();
    let placed = match parts.as_slice() {
        [location, dir, "SKILL.md"] if LOCATIONS.contains(location) => Some((*location, *dir)),
        _ => None,
    };
    if placed.is_none() {
        report(
            Rule::Location,
            format!("must be skills/{{{}}}/<name>/SKILL.md", LOCATIONS.join(",")),
        );
    }

    let front = match parse_skill(text) {
        Ok((front, _)) => front,
        Err(e) => {
            report(Rule::Frontmatter, e);
            return None;
        }
    };

    if !is_kebab(&front.name) {
        report(Rule::Name, format!("`{}` is not kebab-case", front.name));
    } else if let Some((_, dir)) = placed.filter(|(_, dir)| *dir != front.name) {
        report(Rule::Name, format!("`{}` does not match its directory `{dir}`", front.name));
    }

    let description = front.description.trim();
    if description.is_empty() {
        report(Rule::Description, "is empty".into());
    } else if description.chars().count() > MAX_DESCRIPTION {
        report(
            Rule::Description,
            format!("is {} characters, over {MAX_DESCRIPTION}", description.chars().count()),
        );
    }

    let (location, _) = placed?;
    Some(Skill { path: rel.to_path_buf(), location: location.into(), front })
}

fn regenerate(
    text: &str,
    root: &Path,
    skills: &[Skill],
    rel: &Path,
    findings: &mut Vec<Finding>,
) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find(BEGIN) {
        let after_begin = &rest[start + BEGIN.len()..];
        let Some(name_end) = after_begin.find(BEGIN_CLOSE) else { break };
        let name = &after_begin[..name_end];
        let body_start = start + BEGIN.len() + name_end + BEGIN_CLOSE.len();
        let Some(end) = rest[body_start..].find(END) else {
            findings.push(block_finding(rel, format!("no `{END}` after block `{name}`")));
            break;
        };
        let current = &rest[body_start..body_start + end];
        out.push_str(&rest[..body_start]);
        match render(name, root, skills) {
            Ok(content) => {
                let fresh = format!("\n{content}\n");
                if current != fresh {
                    findings.push(block_finding(
                        rel,
                        format!("block `{name}` is stale; run skill-check --write"),
                    ));
                }
                out.push_str(&fresh);
            }
            Err(e) => {
                findings.push(block_finding(rel, e));
                out.push_str(current);
            }
        }
        rest = &rest[body_start + end..];
    }
    out.push_str(rest);
    out
}

fn block_finding(rel: &Path, detail: String) -> Finding {
    Finding { rule: Rule::Block, path: rel.to_path_buf(), detail }
}

fn render(name: &str, root: &Path, skills: &[Skill]) -> Result<String, String> {
    match name {
        "skill-index" => Ok(skill_index(skills)),
        "k3s-deploy-targets" => deploy_targets(root),
        other => Err(format!("unknown generator `{other}`")),
    }
}

fn skill_index(skills: &[Skill]) -> String {
    let mut rows = vec![
        "| Skill | Location | Status | Tools |".to_string(),
        "|:--|:--|:--|:--|".to_string(),
    ];
    for skill in skills {
        let tools = if skill.front.tools.is_empty() {
            "—".to_string()
        } else {
            skill.front.tools.iter().map(|t| format!("`{t}`")).collect::<Vec<_>>().join(", ")
        };
        rows.push(format!(
            "| [`{name}`]({location}/{name}/SKILL.md) | {location} | {status} | {tools} |",
            name = skill.front.name,
            location = skill.location,
            status = skill.front.status,
        ));
    }
    rows.join("\n")
}

/// The targets are the arms of the script's `case "$TARGET" in` dispatch, so
/// the list cannot drift from what the script accepts.
fn deploy_targets(root: &Path) -> Result<String, String> {
    let script = fs::read_to_string(root.join(DEPLOY_SCRIPT))
        .map_err(|e| format!("cannot read {DEPLOY_SCRIPT}: {e}"))?;
    let targets: Vec<String> = script
        .lines()
        .skip_while(|line| !line.contains("case \"$TARGET\" in"))
        .skip(1)
        .take_while(|line| line.trim() != "esac")
        .filter_map(|line| line.trim().strip_suffix(')'))
        .filter(|arm| is_kebab(arm))
        .map(|arm| format!("`{arm}`"))
        .collect();
    if targets.is_empty() {
        return Err(format!("no `case \"$TARGET\" in` arms found in {DEPLOY_SCRIPT}"));
    }
    Ok(targets.join(", "))
}

fn walk(dir: &Path) -> io::Result<Vec<PathBuf>> {
    let mut out = Vec::new();
    walk_into(dir, Path::new(""), &mut out)?;
    out.sort();
    Ok(out)
}

fn walk_into(base: &Path, rel: &Path, out: &mut Vec<PathBuf>) -> io::Result<()> {
    for entry in fs::read_dir(base.join(rel))? {
        let entry = entry?;
        let child = rel.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            walk_into(base, &child, out)?;
        } else {
            out.push(child);
        }
    }
    Ok(())
}
