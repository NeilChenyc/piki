# Home Chat Input Design

## Goal

Make the homepage chat input feel closer to a mature ChatGPT-style product by making it slightly taller and slightly less rounded, while keeping the rest of the Home UI unchanged.

## Scope

- Only adjust the Home chat input container in `PikiApp/PikiApp/Features/Home/ChatInputView.swift`.
- Do not change shadows, borders, icon sizes, button placement, spacing between sections, or message area layout.

## Approved Direction

- Reference feel: ChatGPT style
- Visual character: taller, flatter, restrained
- Approved intensity: option `B`

## Design Decision

- Increase chat input container vertical padding from `12` to `16`
- Reduce chat input container corner radius from `24` to `18`

## Expected Outcome

- The input area reads as more stable and productized
- The shape feels less playful and less pill-like
- The change remains subtle enough to preserve the current overall Home layout

