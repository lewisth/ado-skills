---
name: behavior-spec
description: Build and maintain a BEHAVIOR.md at the solution root capturing the system's expected behaviors in domain-driven (DDD) ubiquitous language. Conduct a relentless one-question-at-a-time interview, exploring every branch of the decision tree, and only create or update the file once you and the user share a complete, unambiguous understanding. Trigger on phrases like "behavior spec", "behavioural spec", "BEHAVIOR.md", "document the domain", "ubiquitous language", "stop AI hallucinating features", "update the behavior spec", or any described behavior change that should be documented. Trigger aggressively on any "behavior"/"behaviour" mention in a spec context — undertriggering is the failure mode to avoid.
---

# Behavior Spec

Produce and maintain `BEHAVIOR.md` at the solution root: the system's expected high-level behaviors in its own domain language, used as the source of truth that future AI work checks itself against.

Grounded in **DDD**: the user's exact terms (no synonyms) and behavior over implementation (*what* the system does and must not do, not *how*).

## The non-negotiable rule

**Do not write or edit the file until you and the user share a complete understanding.** That means every actor, behavior, invariant, and non-goal in scope is concrete; you cannot construct a plausible feature request whose answer isn't already implied; and no sentence in the draft could be read two ways by a reasonable engineer. If any is false, ask another question. The interview ends when ambiguity is exhausted, not when the user gets tired.

## Interview rules

- **One question per turn.** Wait for the answer.
- **Concrete, not abstract.** "What happens when an Order with zero items is submitted?" not "tell me about validation."
- **User's words win.** Lock vocabulary as it emerges; never paraphrase into "cleaner" terms.
- **Depth-first.** Descend into new ambiguity before moving sideways. Close each branch before returning to siblings.
- **Push edges relentlessly.** Zero, boundary, duplicate, concurrent, partial, failure, permission-denied.
- **Surface non-goals.** What should the system *refuse* to do? These prevent hallucinated features more than goals do.

## Workflow

1. **Recon the codebase first.** Layout, entry points (reveal actors), domain folders (vocabulary), persistence (invariants), tests (often half-written specs), existing docs (harvest terminology, don't trust freshness). Look for an existing ubiquitous-language doc (`UBIQUITOUS-LANGUAGE.md`, `GLOSSARY.md`, `DOMAIN.md`, etc.) — if one exists, its terms are authoritative; reference it from Section 2 rather than redefining. If `BEHAVIOR.md` already exists, read it in full; its vocabulary, invariants, and non-goals are locked unless deliberately changed. **Where code answers a question, derive the answer yourself but always confirm with the user** — e.g. "`OrderService` rejects zero-item submissions. Intended behavior or incidental? Hard invariant or just current validation?" Never ask what the code answers; never silently accept what it shows.
1. **Interview** under the rules above until the non-negotiable rule is met. Coverage: actors (can/cannot), core behaviors (Given/When/Then), invariants, non-goals.
1. **Write or update `BEHAVIOR.md`** using the template. When updating, edit only affected sections, append rather than renumber, refresh `_Last reviewed:_`, and log notable removals in Section 7.
1. **Read it back** (or the diff) and iterate until the user confirms.

## BEHAVIOR.md template

Use verbatim. Empty section → `_None._` so it reads as considered, not forgotten.

```markdown
# Behavior Specification

> Expected high-level behaviors of this system in the language of its domain.
> Any change must be consistent with this document. If a change conflicts, this document is updated *first*, deliberately, before code follows.

_Last reviewed: YYYY-MM-DD_

## 1. Purpose
One paragraph, in the user's own words.

## 2. Ubiquitous Language
One canonical term per concept; note deprecated synonyms. Reference an external glossary if one exists.
- **Term** — definition.

## 3. Actors
For each human role, external system, or scheduler:
### 3.1 Actor name
- **Can**: ...
- **Cannot**: ...

## 4. Core Behaviors
### 4.1 Capability name
**Given** ... **When** ... **Then** ...
(Repeat for edge cases and failure modes.)

## 5. Invariants & Business Rules
Numbered, falsifiable statements that must always hold.
1. ...

## 6. Non-Goals
Numbered. Things the system explicitly does not do. Adding any is a scope change requiring an update here first.
1. ...

## 7. Open Questions / Changelog
Deliberate unknowns and notable removals, with owners.
- ...
```

## Anti-patterns

Broad open questions. Paraphrasing the user's terms. Documenting frameworks or file paths (wrong document). Stopping at the first plausible draft. Assuming "common sense" for edges. Skipping recon — an interview without codebase grounding is just a survey.
