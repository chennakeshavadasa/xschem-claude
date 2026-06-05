# Retrospective: best-practice slips of a new Claude Code user

A candid, specific retrospective from this project's first long session, graded
against best practice — not to scold, but so the patterns are reusable. Pairs
with `using_claude_for_ui_ux_refactoring.md` and `llm_on_a_hairball.md`.

## What was violated

### 1. The objective arrived last, after the analysis (the big one)
The session went: `/init` → coding style → orthogonality → call graph → layering
→ "un-hairball fruit" → "readability/maintainability/extensibility" → *"actually,
what we care about is UX."* The real goal surfaced ~8 turns in, after a lot of
measurement. Best practice is the reverse: **state the objective first; let
analysis serve it.** The risk-map work was reusable, but the style/orthogonality
essays were interesting-not-actionable for a UX goal. Analysis was paid for
before it was needed.

### 2. The tool was never run — while optimizing its UX
Everything was static analysis plus a *headless* netlist harness. For a UX goal
that's a real gap: you can't refactor a feel you haven't felt, and the LLM is
blind to the rendered window. The actual GUI should be driven and its concrete
friction written down *before* building UI features. (Not even attempted yet.)

### 3. One enormous session
Init, analysis, git/publishing, refactor, and planning all live in a single
conversation — long enough that context gets summarized. Distinct objectives are
better as **focused sessions**; start fresh when the goal changes.

### 4. Acted against a stated constraint on an irreversible action
Stated a wish to keep the email private, was warned the address would be public
on push, chose public anyway. That's a valid choice — but the pattern to catch is:
on **irreversible / outward-facing actions** (publishing a repo, exposing an
email), slow down rather than push through. (Also: published a full public clone
of someone else's GPL project under a personal account — legal, but a
deliberate-choice-worth-pausing-on.)

### 5. Commit cadence was late
The first commit came only on "save the work so far," after CLAUDE.md, the
harness, and several analysis docs already existed as an untracked pile. Smaller,
earlier, logically-scoped commits are cheap checkpoints.

### 6. Recurring friction left unconfigured
The git-identity prompt and sandbox push failures recurred. A new user can set up
`settings.json` (command allowlists, env) once to smooth this.

## What was done right (so the feedback is calibrated)
- **Insisted on verification** — accepted "prove it" over "trust me" from the
  start. The single most important habit.
- **Captured decisions in text** — which is why this work is reusable instead of
  evaporating.
- **Allowed stop-and-confirm before outward-facing actions** (public/private,
  scope) instead of barreling ahead.

## The one habit that fixes most of the above
**Lead with the objective and a definition of "done."** Had turn one been *"the
tool's UX is poor; I want to enable UX improvements — where's the leverage?"*, the
work would have gone straight to the menu/keysym/action-registry finding and
skipped a couple of essays. Analysis is a tool in service of a decided goal, not
a warm-up.

## Concrete checklist for next time
- [ ] State the objective and "done" criteria in the first message.
- [ ] For UX work, run and observe the real app before refactoring.
- [ ] One objective per session; start fresh when the goal shifts.
- [ ] Commit small and early; don't accumulate untracked piles.
- [ ] Pause on irreversible/public actions; reconcile them with stated constraints.
- [ ] Configure `settings.json` once to kill recurring friction.
- [ ] Keep verification and decision-capture (already strong — keep doing it).
