Yes. For a serious mock-test/PYQ platform, I’d make the question model a bit richer now rather than discovering painful edge cases after importing thousands of SSC papers.

The biggest design principle is: **separate the question itself from where/how it appeared in an exam**. The same underlying question can theoretically appear in multiple papers, shifts, mock tests, or translated versions.

A practical model could look like this:

```text
Question
---------
id
question_type
question_text
language
subject
topic
subtopic
difficulty

group_id            # nullable
media[]             # images/charts/figures
options[]
correct_answer
explanation

source_id
status
created_at
updated_at
```

But I would add several important concepts around it.

### 1. Question type

Don't assume everything is just `MCQ`.

```text
question_type:
    single_choice
    multiple_choice
    numeric
    text
```

For SSC CGL today you'll mostly encounter single-choice MCQs, but supporting the others makes your engine reusable for other exams later.

---

### 2. Question groups

As we discussed:

```text
QuestionGroup
-------------
id
type

common_text
common_media[]

questions[]
```

Types could include:

```text
reading_comprehension
data_interpretation
cloze_test
puzzle
caselet
common_instructions
```

For example:

```text
QuestionGroup

type: data_interpretation

common_media:
    pie_chart.png

questions:
    Q41
    Q42
    Q43
    Q44
    Q45
```

This is probably the most important non-obvious modeling decision.

---

### 3. Rich content instead of plain strings

I wouldn't make `question_text` just a plain string.

Questions can contain:

* mathematical expressions
* superscripts/subscripts
* tables
* diagrams
* images
* highlighted text
* underlining
* blanks
* passages

So consider something like:

```json
{
  "content": [
    {
      "type": "text",
      "value": "If x² + 3x..."
    },
    {
      "type": "image",
      "url": "..."
    }
  ]
}
```

Or use sanitized HTML/Markdown + separate media references.

This will save you a lot of trouble when importing PDFs.

---

### 4. Options should be objects

Don't store:

```json
["10", "20", "30", "40"]
```

Prefer:

```json
[
  {
    "id": "A",
    "content": "10"
  },
  {
    "id": "B",
    "content": "20"
  },
  {
    "id": "C",
    "content": "30"
  },
  {
    "id": "D",
    "content": "40"
  }
]
```

Because options themselves may contain:

* images
* equations
* tables
* formatting

And you don't want the correct answer tied to array position.

---

### 5. Separate Question from ExamQuestion

This one matters a lot.

Don't put things like:

```text
question_number = 53
shift = 2
marks = 2
```

directly on `Question`.

Instead:

```text
ExamQuestion
------------
exam_paper_id
question_id

question_number
section
sequence
marks
negative_marks

group_sequence
```

Because those properties belong to the **appearance of the question in a particular paper**, not the question itself.

For example:

```text
Question #abc123

appeared in:

SSC CGL 2024
Tier 1
12 Sep 2024
Shift 2
Question 53
Quantitative Aptitude
2 marks
```

---

### 6. Model the entire exam hierarchy

I'd probably use something along these lines:

```text
Exam
  SSC CGL

ExamTier
  Tier 1

ExamPaper
  year: 2024
  date: 2024-09-12
  shift: 2

Section
  General Intelligence
  General Awareness
  Quantitative Aptitude
  English

ExamQuestion
  Q1
  Q2
  ...
```

That lets you recreate the **exact original paper**.

---

### 7. Preserve original numbering

Keep both:

```text
sequence
original_question_number
```

Why?

Suppose your importer fails to extract Q47.

You may have:

```text
sequence: 46
original_number: 46

sequence: 47
original_number: 48
```

If you only store your internal sequence, you lose correspondence with the PDF.

Very useful when debugging extraction.

---

### 8. Source/provenance

Since you're planning to collect PYQs, this is crucial.

```text
QuestionSource
--------------
source_type: official_pdf / coaching_pdf / website
source_url
source_document
page_number

exam
year
date
shift

verified
verification_method
```

Then you can distinguish:

> "SSC official answer"

from:

> "Answer claimed by coaching website X."

That's important because unofficial PYQ sources sometimes contain incorrect answers or reconstructed wording.

---

### 9. Answer provenance

Similarly, don't just store:

```text
correct_answer = B
```

Consider:

```text
Answer
------
correct_option
source

official_answer: true/false
confidence

explanation
explanation_source
```

You may later discover:

```text
website says B
official SSC key says C
```

You don't want to overwrite history.

---

### 10. Bilingual questions

SSC papers can involve both **Hindi and English representations**, so avoid duplicating entire questions unnecessarily.

You could model:

```text
QuestionTranslation
-------------------
question_id
language

question_text
options
explanation
```

Then:

```text
Question
  ├── English
  └── Hindi
```

This also makes your platform expandable to regional-language exams.

---

### 11. Classification should support multiple tags

Don't lock yourself into just:

```text
subject = Maths
topic = Algebra
```

A question may reasonably have:

```text
Subject:
Quantitative Aptitude

Topic:
Arithmetic

Subtopic:
Percentage

Tags:
percentage
profit-loss
successive-percentage
calculation-heavy
```

So use a tagging relation rather than one giant enum.

---

### 12. Difficulty should probably not be a fixed truth

Instead of:

```text
difficulty = HARD
```

eventually you'll have useful data:

```text
attempts = 12,430
correct = 4,218

accuracy = 33.9%
average_time = 78 sec
```

Then difficulty can be calculated based on actual candidate performance.

You may still keep:

```text
editor_difficulty
```

separately.

---

### 13. User-attempt model should be separate

Don't modify Question when someone answers it.

Something like:

```text
QuestionAttempt
---------------
user_id
question_id
test_attempt_id

selected_option
is_correct

started_at
answered_at
time_taken_ms

marked_for_review
visited
```

This allows analytics such as:

```text
Accuracy by topic
Average solving time
Strong/weak areas
Questions frequently skipped
```

---

### 14. Preserve ordering inside groups

For grouped questions:

```text
group_id = DI_123

group_sequence:
1
2
3
4
5
```

This is different from paper question numbering.

For example:

```text
Paper Q51 → DI question 1
Paper Q52 → DI question 2
...
```

---

### 15. Support question corrections/versioning

This becomes surprisingly important with PYQs.

Suppose you initially extract:

> ₹5400

but later discover the PDF actually said:

> ₹5,400 per annum

Instead of silently changing it, keep something like:

```text
QuestionRevision
----------------
question_id
version

old_content
new_content

reason
changed_at
```

Especially useful if thousands of users have already attempted that question.

---

### 16. Deduplication / canonical questions

When scraping from multiple sources, you'll almost certainly encounter:

```text
same question
slightly different formatting
different source
```

Have:

```text
canonical_question_id
```

or a similarity/deduplication layer.

For example:

```text
Source A:
What is 20% of 500?

Source B:
Find 20 percent of 500.

Canonical Question:
Q12345
```

But be conservative when automatically merging; tiny wording differences can change a question.

---

### I'd therefore structure the core roughly like this

```text
Exam
 └── ExamTier
      └── ExamPaper
           ├── Sections
           │
           └── ExamQuestion ───────────┐
                                      │
                                      ▼
                                  Question
                                      │
                  ┌───────────────────┼───────────────┐
                  ▼                   ▼               ▼
             QuestionGroup       Translation        Options
                  │
             Common content
             Common images


Question
 ├── Topic / Tags
 ├── Media
 ├── Answer(s)
 ├── Explanation
 ├── Source(s)
 └── Revision history


UserTestAttempt
 └── QuestionAttempt
```

One architectural choice I'd **strongly recommend for your Mock Test Website** is making `Question` and `ExamQuestion` separate entities. That gives you a clean distinction between **question-bank data** and **paper/test composition**, and it makes features like custom mocks, topic tests, PYQ tests, duplicate detection, analytics, and question reuse much easier later.
