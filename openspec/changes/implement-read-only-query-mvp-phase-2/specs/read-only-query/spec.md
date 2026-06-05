## ADDED Requirements

### Requirement: Index-first query context
The system SHALL load `wiki/index.md` before executing a `query` task and SHALL include that page in the query context manifest.

#### Scenario: Query loads index first
- **WHEN** a user creates a `query` task for a valid vault
- **THEN** the task events include `context.loaded` with `wiki/index.md` listed as a loaded file

### Requirement: Chinese-friendly Markdown recall
The system SHALL search compiled Markdown wiki pages using exact matching, ASCII tokens, Chinese character tokens, and CJK bigrams.

#### Scenario: Chinese query recalls matching page
- **WHEN** a user asks a Chinese query containing terms that appear in a compiled wiki page
- **THEN** the query result includes that page in citations or related pages

### Requirement: Wikilink recall expansion
The system SHALL expand initial search hits through wikilinks and include matching linked wiki pages as related pages.

#### Scenario: Linked page appears as related context
- **WHEN** an initially matched wiki page links to another existing wiki page
- **THEN** the query result includes the linked page as a related page

### Requirement: Citation output
The system SHALL return citations for query answers, including wiki page path, title, and line number when available.

#### Scenario: Query returns cited answer
- **WHEN** a query task completes with matching wiki content
- **THEN** the task output contains at least one citation with path, title, and line fields

### Requirement: Recall modes
The system SHALL support quick answer, deep answer, and related-pages-only query modes.

#### Scenario: Related pages mode suppresses prose answer
- **WHEN** a user creates a query task with mode `related`
- **THEN** the task output returns related pages and uses an answer indicating that only related pages were requested

### Requirement: Read-only query behavior
The system SHALL NOT modify vault files during `query` tasks.

#### Scenario: Query does not write wiki log
- **WHEN** a query task completes
- **THEN** existing vault files such as `wiki/log.md` remain unchanged

### Requirement: Raw source avoidance
The system SHALL NOT read files under `raw/` during default query recall.

#### Scenario: Query context excludes raw sources
- **WHEN** a default query task completes
- **THEN** the task output context manifest and citations contain only `wiki/` pages and baseline files

### Requirement: Structured query output
The system SHALL persist structured query output on the task record.

#### Scenario: Task inspection includes query result
- **WHEN** a completed query task is fetched through `GET /tasks/{id}`
- **THEN** the response includes output data with answer, citations, related pages, confidence, and next actions
