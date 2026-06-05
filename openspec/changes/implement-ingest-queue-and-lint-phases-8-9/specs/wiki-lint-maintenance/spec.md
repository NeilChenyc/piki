## ADDED Requirements

### Requirement: Generate lint report
The system SHALL generate a deterministic wiki lint report.

#### Scenario: Run lint
- **WHEN** a client requests lint for a vault
- **THEN** the response includes issue counts, issue list, scanned files, and fixable issue ids

### Requirement: Detect structural issues
The lint workflow SHALL detect common structural wiki issues.

#### Scenario: Missing frontmatter
- **WHEN** a wiki Markdown page lacks YAML frontmatter
- **THEN** lint reports a missing frontmatter issue

#### Scenario: Broken wikilink
- **WHEN** a wiki page links to a non-existent wiki page
- **THEN** lint reports a broken link issue

#### Scenario: Orphan page
- **WHEN** a wiki page has no incoming wikilinks and is not `wiki/index.md` or `wiki/log.md`
- **THEN** lint reports an orphan page issue

#### Scenario: Missing index entry
- **WHEN** a wiki page is not referenced from `wiki/index.md`
- **THEN** lint reports a missing index entry issue

### Requirement: Detect maintenance issues
The lint workflow SHALL detect stale markers, duplicate titles, thin pages, and repeated undefined concepts.

#### Scenario: Stale check_after
- **WHEN** a page contains `check_after` date on or before the current date
- **THEN** lint reports a stale page issue

#### Scenario: Repeated undefined concept
- **WHEN** the same bracketed concept-like phrase appears repeatedly without a matching wiki page
- **THEN** lint reports a knowledge gap issue

### Requirement: Apply low-risk lint fixes
The system SHALL apply narrow low-risk lint fixes when requested.

#### Scenario: Fix missing index entries
- **WHEN** a client requests lint fix for missing index entries
- **THEN** the system appends links to `wiki/index.md`, appends a lint log entry to `wiki/log.md`, and records a journal entry if wiki files changed
