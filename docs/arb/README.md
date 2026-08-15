# Architecture review board records

Numbered, dated records of design decisions that touch the code's semantics,
the spec, or the style guide. The board is the signalling cabin's log: when
a later commit questions a decision, the record is the first place to look —
it says what was decided, why, and what the alternatives cost.

**Format.** One file per decision: `NNNN-short-title.md`, written when the
decision is made, not afterwards, and landing in the same commit as the
change it describes.

**A record answers four questions:**

- What was decided?
- Why now — what forced the decision?
- What was rejected, and why?
- What breaks, and who absorbs the cost?

**Status.** `Accepted` (we are doing this), `Proposed` (under review), or
`Superseded by NNNN` (a later record replaced it).
