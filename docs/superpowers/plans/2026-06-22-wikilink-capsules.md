# WikiLink Capsule Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render `[[category/page]]` references as clickable, category-colored capsules in shared Markdown rendering, and route clicks to the matching Wiki page.

**Architecture:** Keep the Markdown source untouched and add a render-layer `wikilink` parser shared by Home and Wiki. Resolve targets through `WikiViewModel`, and reuse a single capsule component for inline references and the related-links section.

**Tech Stack:** SwiftUI, Swift Testing, `swift-markdown`

---

### Task 1: Add failing tests for wikilink parsing and page resolution

**Files:**
- Create: `PikiApp/Tests/PikiAppTests/WikiLinkRenderingTests.swift`

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run the targeted test to verify it fails**
- [ ] **Step 3: Implement the minimal parsing and resolution helpers**
- [ ] **Step 4: Run the targeted test to verify it passes**

### Task 2: Render clickable capsules in shared Markdown UI

**Files:**
- Modify: `PikiApp/PikiApp/SharedUI/Components/MarkdownTextView.swift`
- Create: `PikiApp/PikiApp/SharedUI/Components/WikiLinkCapsule.swift`
- Create: `PikiApp/PikiApp/Features/Wiki/WikiLinkSupport.swift`

- [ ] **Step 1: Add shared `wikilink` models and category styling**
- [ ] **Step 2: Replace plain inline rendering for `[[...]]` spans with capsule-aware rendering**
- [ ] **Step 3: Keep non-wikilink Markdown rendering intact**
- [ ] **Step 4: Run the targeted test suite and confirm it stays green**

### Task 3: Connect Home and Wiki navigation

**Files:**
- Modify: `PikiApp/PikiApp/Features/Wiki/WikiViewModel.swift`
- Modify: `PikiApp/PikiApp/Features/Wiki/WikiPageContentView.swift`
- Modify: `PikiApp/PikiApp/Features/Home/ChatBubbleView.swift`
- Modify: `PikiApp/PikiApp/Features/Home/HomeView.swift`
- Modify: `PikiApp/PikiApp/Features/Wiki/WikiView.swift`
- Modify: `PikiApp/PikiApp/PikiApp.swift`

- [ ] **Step 1: Add lookup/select helpers to `WikiViewModel`**
- [ ] **Step 2: Pass click handlers into shared Markdown rendering**
- [ ] **Step 3: Reuse the capsule component for related links**
- [ ] **Step 4: Run app-level verification with `swift test` and `swift build`**
