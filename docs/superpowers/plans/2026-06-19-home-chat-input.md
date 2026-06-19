# Home Chat Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adjust the Home chat input to a slightly taller, less rounded ChatGPT-like profile without changing any other Home UI styling.

**Architecture:** This is a single-view presentation change in the SwiftUI Home input component. The implementation only updates the container's vertical padding and corner radius so the visual adjustment stays tightly scoped.

**Tech Stack:** SwiftUI, Swift Package Manager, macOS app target

---

### Task 1: Update Home Chat Input Container Styling

**Files:**
- Modify: `PikiApp/PikiApp/Features/Home/ChatInputView.swift`
- Verify: `PikiApp/build-app.sh`

- [ ] **Step 1: Update the approved sizing values**

```swift
.padding(.horizontal, 16)
.padding(.vertical, 16)
.background(
    RoundedRectangle(cornerRadius: 18)
        .fill(Theme.cardBackground)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
)
```

- [ ] **Step 2: Build the macOS app to verify the SwiftUI change compiles**

Run: `./build-app.sh`
Expected: `swift build` succeeds and the script prints `Built: .../Piki.app`

