# AI Chat

Keywords: AI, translation, explanation, summary, selected text, follow-up questions, streaming, API key.

The AI panel explains, summarizes, and translates selected text and supports follow-up questions about the current reading context. If no API key is configured, the app directs the user to Settings.

## Entry Points

- The selected-text toolbar offers Explain, Translate, Summarize, and Ask actions.
- The side panel can summarize or translate the current content and continue a conversation.
- The vocabulary popover can request an AI explanation and append local dictionary tags.
- Reading Notes can send text for AI organization while preserving image placeholders.

## Conversation Behavior

User and assistant bubbles appear in conversation order. Assistant responses support Markdown copying, and ordinary responses can be regenerated. Bubbles with source locations can return to and highlight the matching passage.

Streaming updates are throttled before rendering to avoid relayout for every token. Recent conversations are trimmed to limit startup and restoration work.

## Request Flow

```text
Selected text or current reading context
  -> AIChatPanel collects context
  -> Actions build the request
  -> Requests manage streaming, retry, and cancellation
  -> AIClient sends the request
  -> Bubbles render and persist the response
```

## Main Files

- `AIChatPanel.swift`: panel state and selected-text entry point.
- `AIChatPanel+Actions.swift`: summary, translation, and follow-up actions.
- `AIChatPanel+Requests.swift`: request lifecycle, retry, cancellation, and error mapping.
- `AIChatPanel+Bubbles.swift`: bubble creation, rendering, layout, and scrolling.
- `AIChatPanel+Conversation.swift`: saved-conversation restoration.
- `AIChatPanel+Export.swift`: conversation copy and export.
- `AIClient.swift`: HTTP and streaming response client.
- `AIPromptStore.swift` and `Resources/AIPrompts.json`: built-in prompt templates.

All AI entry points should use the shared model-configuration check so missing credentials produce consistent guidance.
