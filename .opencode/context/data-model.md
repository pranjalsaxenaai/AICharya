# Data model — phase 1 (PostgreSQL)

Decided model for the SSC CGL question bank. Requested by the user; analyzed
against another agent's proposal in `doc/DataModel.md`, then finalized as
`doc/schema.sql` (13 tables).

## Core principle
**Question-bank data is separate from paper composition.**
A `Question` is reusable content (same stem can appear in multiple shifts,
mocks, languages). An `ExamQuestion` is one *appearance* of a `Question` in
one `ExamPaper` (that's where number/section/marks live).

## Entity map
```
exam → exam_tier → exam_paper → paper_section → exam_question → question
                                                              ├─ question_group (RC/DI/cloze share a common stem)
                                                              ├─ question_tag        (taxonomy tree)
                                                              ├─ question_media      (images/charts)
                                                              └─ answer_source       (provenance, never overwrite history)
```
Plus `tag` taxonomy and `media` storage tables.

## Key decisions
- `exam_paper` keeps **cycle** (`2019`) separate from **conducted_date**
  (`2020-03-06`) — CGL 2019 was physically held in two periods (Jun 2019 and
  Mar 2020). This was the main flaw in the other agent's sketch (single
  `year/date`).
- Language is a property of the `question` row (`en`/`hi`); EN/HI variants of
  the same stem are paired via `translation_group_id`. No separate
  translation table needed.
- `paper.kind` distinguishes `official` vs `similar`/memory-based vs
  `coaching` — the 2025 set is reconstructed ("similar"), not official.
- `status` lifecycle on `question` and `exam_paper`: `draft → reviewed →
  published` (AI extraction is error-prone).
- Dedup via `fingerprint_md5` + nullable `canonical_id`; never auto-merge,
  only flag candidates.
- `question_type` is single-choice only for now; extensible later
  (no free-text/numeric for SSC, Tier 3 is a separate paper).
- Deferred to phase 2 (separate system): users, test attempts, analytics,
  revisions, computed difficulty.

## Files
- `doc/schema.sql` — full PostgreSQL DDL
- `doc/DataModel.md` — the original proposal being analyzed