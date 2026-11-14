# Imladris User Study — Methodology & Provenance

**App under test:** Imladris 0.24.2 (`/home/antonio/Projects/imladris/build-deb/imladris`, commit `38dc3d5`)
**Study brief:** [User-study-implementation.md](../User-study-implementation.md)
**Date:** 2026-11-13

## Approach (Elephant / Goldfish)

- **Elephant (the coordinator):** holds the whole context (the codebase history, earlier audits, the brief). It writes the persona briefs, gathers the results, runs the statistics, and decides what to prioritise.
- **Goldfish (the persona evaluators):** each one starts with no memory of earlier work and no knowledge of the other personas. It sees only its own persona profile and the codebase. This keeps the feedback **unbiased and independent**.
- Each persona returns the same structure:
  1. Four scores from 1.0 to 5.0: `ux`, `learnability`, `reliability`, `feature_fit`
  2. Bugs and errors, with file and line references
  3. UX friction points
  4. Missing features, each tagged `[CORE]` or `[PLUGIN]`
  5. What worked well

## Evaluation provenance (read this before using the numbers)

| Persona | Evaluated by | Independence |
|---|---|---|
| G2-1 Biochemistry Professor | Independent Goldfish agent (`egm-scientist-user`) | ✅ Independent |
| G2-2 Bioinformatics BSc Freshman | Independent Goldfish agent (`egm-scientist-user`) | ✅ Independent |
| G2-3 Wet-Lab → Dry-Lab Scientist | Independent Goldfish agent (`egm-scientist-user`) | ✅ Independent |
| G1-1, G1-2, G1-3, G1-4, G1-5, G2-4, G2-5 | Coordinator, using direct code inspection | ⚠️ Not independent |

> [!WARNING]
> Ten persona agents were launched. They all stopped because of model quota limits (`RESOURCE_EXHAUSTED 429`) and a later server restart. Only the G2-1…G2-3 cohort sent back a full report, and it is saved here **word for word**.
> The other 7 reports were written by the coordinator. Each finding in them was checked against the source code with `grep` and direct file reads, and every finding cites file and line. Their **scores are coordinator estimates**. They are not independent user judgements.
> Because of this, any difference between Group 1 and Group 2 scores is **mixed up with who did the evaluating**. Re-run the 7 personas with independent agents once quota resets, then treat the results as final.

## Files

| File | Content |
|---|---|
| `G1-1-clinical-bioinformatician.md` … `G1-5-enterprise-biostatistician.md` | Group 1 persona reports |
| `G2-1-G2-3-independent-agent-report.md` | Group 2 cohort report (independent agent, saved word for word) |
| `G2-4-returning-msc-student.md`, `G2-5-modern-linux-phd.md` | Group 2 persona reports |
| `99-statistical-analysis.md` | Score statistics, theme frequencies, priority ranking, and Core vs Plugin classification |
