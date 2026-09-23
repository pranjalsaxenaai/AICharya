-- SSC CGL question bank — phase 1 schema (PostgreSQL)
-- Core principle: question-bank data is separate from paper composition.
-- A Question is reusable across shifts/mocks; an ExamQuestion is one
-- appearance of a question in one paper.

BEGIN;

-- ============================================================================
-- Exam hierarchy
-- ============================================================================

CREATE TABLE exam (
    id         bigserial PRIMARY KEY,
    code       text NOT NULL UNIQUE,                 -- 'CGL', 'CHSL'
    name       text NOT NULL                        -- 'Staff Selection Commission – Combined Graduate Level'
);

CREATE TABLE exam_tier (
    id       bigserial PRIMARY KEY,
    exam_id  bigint NOT NULL REFERENCES exam(id),
    code     text NOT NULL,                          -- '1', '2', '3'
    name     text NOT NULL,                          -- 'Tier 1'
    seq      int  NOT NULL DEFAULT 0,
    UNIQUE (exam_id, code)
);

-- One row per physical paper variant (language versions are separate rows).
-- cycle  == exam cycle (e.g. CGL 2019)  -- NOT the conducted date.
-- CGL 2019 was conducted 4-19 Jun 2019 AND 3-9 Mar 2020; cycle stays 2019.
CREATE TABLE exam_paper (
    id             bigserial PRIMARY KEY,
    tier_id        bigint NOT NULL REFERENCES exam_tier(id),
    cycle          int    NOT NULL,                  -- 2019
    conducted_date date,                             -- 2020-03-06
    shift_no       smallint NOT NULL DEFAULT 1,
    language       text NOT NULL DEFAULT 'en' CHECK (language IN ('en','hi')),
    kind           text NOT NULL DEFAULT 'official' CHECK (kind IN ('official','similar','coaching','answer_key')),
    status         text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','validated','published')),
    source_url     text,                             -- original PDF host page / direct link
    notes          text,
    created_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tier_id, cycle, conducted_date, shift_no, language)
);

CREATE TABLE paper_section (
    id             bigserial PRIMARY KEY,
    paper_id       bigint  NOT NULL REFERENCES exam_paper(id) ON DELETE CASCADE,
    name           text NOT NULL,                    -- 'General Intelligence and Reasoning'
    code           text,                             -- 'GIR', 'GA', 'QA', 'English'
    seq            int NOT NULL DEFAULT 0,
    positive_marks numeric,                          -- NULL => read from exam_question
    negative_marks numeric,
    UNIQUE (paper_id, seq)
);

-- ============================================================================
-- Question content (the bank)
-- ============================================================================

-- Taxonomy, not free strings.
CREATE TABLE tag (
    id        bigserial PRIMARY KEY,
    name      text NOT NULL UNIQUE,
    parent_id bigint REFERENCES tag(id)
);

CREATE TABLE question (
    id                  bigserial PRIMARY KEY,
    translation_group_id bigint,                      -- pairs en/hi variants of the same question (nullable)
    language            text NOT NULL DEFAULT 'en' CHECK (language IN ('en','hi')),
    question_type       text NOT NULL DEFAULT 'single_choice' CHECK (question_type IN ('single_choice')),
    stem_json           jsonb NOT NULL,               -- ordered blocks [{type:'text'|'image'|'table', value, media_id?}]
    options_json        jsonb,                        -- [{id, content:[blocks]}] or NULL for non-MCQ
    correct_answer      jsonb NOT NULL,               -- {"option_id":"B"} or {"numeric":5400}
    explanation         text,
    editor_difficulty   smallint CHECK (editor_difficulty BETWEEN 1 AND 5), -- editorial guess only
    status              text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','reviewed','published')),
    fingerprint_md5     text,                         -- normalized-text hash for dedup candidate finding
    canonical_id        bigint REFERENCES question(id), -- self-ref dedup target (nullable)
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX question_translation_group_idx ON question (translation_group_id);
CREATE INDEX question_fingerprint_idx       ON question (fingerprint_md5);

CREATE TABLE question_tag (
    question_id bigint NOT NULL REFERENCES question(id) ON DELETE CASCADE,
    tag_id      bigint NOT NULL REFERENCES tag(id),
    PRIMARY KEY (question_id, tag_id)
);

CREATE INDEX question_tag_tag_idx ON question_tag (tag_id);

-- ============================================================================
-- Question groups (RC passage, DI chart, cloze)
-- ============================================================================

CREATE TABLE question_group (
    id          bigserial PRIMARY KEY,
    type        text NOT NULL CHECK (type IN ('reading_comprehension','data_interpretation','cloze_test','common_instructions')),
    language    text NOT NULL DEFAULT 'en',
    stem_json   jsonb,                               -- passage text / chart description as blocks
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE group_question (
    group_id        bigint NOT NULL REFERENCES question_group(id) ON DELETE CASCADE,
    question_id     bigint NOT NULL REFERENCES question(id) ON DELETE CASCADE,
    group_sequence  int NOT NULL DEFAULT 1,
    PRIMARY KEY (group_id, question_id)
);

CREATE INDEX group_question_question_idx ON group_question (question_id);

-- ============================================================================
-- Media (shared, referenced from stem/options JSON blocks)
-- ============================================================================

CREATE TABLE media (
    id           bigserial PRIMARY KEY,
    kind         text NOT NULL CHECK (kind IN ('image','chart','table','audio')),
    storage_path text NOT NULL,                       -- filesystem/object-store path
    sha256       text,
    width        int,
    height       int,
    size_bytes   bigint
);

CREATE TABLE question_media (
    question_id bigint NOT NULL REFERENCES question(id) ON DELETE CASCADE,
    media_id    bigint NOT NULL REFERENCES media(id),
    position    int NOT NULL DEFAULT 0,               -- block index within stem/options
    PRIMARY KEY (question_id, media_id)
);

-- ============================================================================
-- Paper composition: the appearance of a question in a paper
-- ============================================================================

CREATE TABLE exam_question (
    id                   bigserial PRIMARY KEY,
    paper_id             bigint NOT NULL REFERENCES exam_paper(id) ON DELETE CASCADE,
    section_id           bigint REFERENCES paper_section(id),
    question_id          bigint NOT NULL REFERENCES question(id),
    group_id             bigint REFERENCES question_group(id),   -- NULL => standalone
    original_question_no int,                                    -- number printed in PDF
    sequence             int NOT NULL,                           -- our ordering within section
    marks                numeric NOT NULL DEFAULT 1,
    negative_marks       numeric NOT NULL DEFAULT 0,
    group_sequence       int,                                   -- order inside group if grouped
    UNIQUE (paper_id, original_question_no),
    UNIQUE (paper_id, sequence)
);

CREATE INDEX exam_question_question_idx ON exam_question (question_id);
CREATE INDEX exam_question_group_idx    ON exam_question (group_id);

-- ============================================================================
-- Answer provenance (never overwrite history)
-- ============================================================================

CREATE TABLE answer_source (
    id             bigserial PRIMARY KEY,
    question_id    bigint NOT NULL REFERENCES question(id) ON DELETE CASCADE,
    source_kind    text NOT NULL CHECK (source_kind IN ('official_key','coaching','auto_extracted','manual_review')),
    source_url     text,
    source_document text,                              -- e.g. named PDF + page number
    page_number    int,
    claimed_answer jsonb,
    is_official    boolean NOT NULL DEFAULT false,
    confidence     numeric CHECK (confidence BETWEEN 0 AND 1), -- for auto-extracted
    note           text,
    created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX answer_source_question_idx ON answer_source (question_id);

COMMIT;