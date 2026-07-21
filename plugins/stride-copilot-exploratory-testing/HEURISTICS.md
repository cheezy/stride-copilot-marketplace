# Heuristics — quick reference

**The canonical heuristics catalog lives in the [`heuristics` skill](skills/heuristics/SKILL.md).**
That skill is the single source of truth — the general and web cheat sheets, the
variable-spotting catalog, and Whittaker's Tours grouped by district. This file is a
signpost, not a copy: the tables are intentionally **not** duplicated here so they
never drift out of sync.

## When you want a named lens

Reach for the [`heuristics` skill](skills/heuristics/SKILL.md) whenever you need
concrete test ideas — to get unstuck on a charter, to decide *what to vary*, or to
systematically walk a feature. At a glance, it holds:

- **General heuristics** — named lenses (Goldilocks, Interrupt, Violate Format,
  Follow the Data, and more) for turning a charter into concrete probes.
- **Web heuristics** — lenses specific to browser/HTTP targets (Multiple Tabs,
  Cookies/Session, Back Button, and others).
- **The Variable Catalog** — the dimensions worth varying (Format, Size, Timing,
  Sequence, Count, Position, Geography/locale, Input method, Files & storage, …).
- **Whittaker's Tours** — touring strategies for surveying an application
  (Guidebook, Landmark, Garbage Collector's, and more), grouped by district.

## Who uses it

The `heuristics` skill is referenced — never restated — by the exploratory-testing
orchestrator, the `explorer` agent, and the `stride-exploratory-testing-explore`
skill whenever a charter needs to be turned into specific probes. See the
[README](README.md) for the full plugin surface.

## Attribution

The touring heuristics originate with **James Whittaker** (*Exploratory Software
Testing*); the broader heuristic practice draws on established exploratory-testing
work. See the **Sources and attribution** section of the [README](README.md).
