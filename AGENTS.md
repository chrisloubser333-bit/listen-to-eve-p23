# Primary Senior Engineering Agent: Listen to Eve

## Project Rules

### 1. Existing Project
- This is an existing production-oriented Flutter application (with source located in `flutter_source/` and preview web companion in `src/`).
- Do NOT rebuild the application from scratch.
- Do NOT migrate the project to another framework.
- Preserve the existing Flutter architecture unless a migration is explicitly requested.
- Before changing code, inspect the existing implementation and understand how the relevant feature currently works.

### 2. Safety First
Before making significant changes:
- Inspect the relevant files;
- Identify dependencies;
- Identify existing providers/services/state management;
- Identify how the feature is currently connected to the UI;
- Identify possible regressions;
- Make the smallest safe change.
- Never delete working functionality simply because a cleaner implementation is possible.

### 3. Testing
For every coding task:
- Run the appropriate analyzer/tests/build checks available in the environment;
- Inspect errors and warnings;
- Fix regressions caused by the change;
- Verify the affected UI behaviour in preview where supported;
- Report exactly what was changed and what was tested.
- Note: If Flutter tooling is unavailable in the current environment, explicitly state so instead of pretending that the Flutter application compiled successfully.

### 4. UI
Listen to Eve is a mobile-first application.
Preserve:
- The existing polished dark visual direction;
- The human avatar presentation;
- Eve, Ara, Leo, Rex, and Sal as distinct characters;
- Character-specific names, accents, voices, and personalities;
- The avatar remaining visible while conversation content scrolls underneath;
- Smooth conversational interaction.
- Do not replace the established UI with generic AI-chat styling.

### 5. Character System
Each character must have independent:
- Name;
- Personality;
- Voice;
- Avatar;
- Status;
- Conversation context.
- Never hard-code Eve-specific states into shared character UI (e.g. another character must never display "Eve is thinking" when that character is active).

### 6. Memory
The existing persistent memory architecture is fundamental to Listen to Eve.
Preserve the separation between:
- Working memory;
- Semantic facts;
- Preferences;
- Episodic events;
- Relationship/context;
- Skills/domain knowledge;
- Memory extraction;
- Importance scoring;
- Reinforcement;
- Semantic indexing/retrieval;
- Decay.
- Memory must remain model-independent.
- Changing the selected AI provider/model must NOT erase or invalidate the user's existing memories.

### 7. AI Provider Architecture
- Maintain provider abstraction.
- Do not tightly couple the application's intelligence or memory system to one model provider.
- The application must remain capable of supporting selectable AI models/providers.

### 8. Conversation Quality
The goal is natural human-like conversation.
Avoid unnecessarily robotic:
- Headings;
- Numbered explanations;
- Repetitive confirmations;
- Generic AI disclaimers;
- Excessive verbosity.
- Responses should use conversation history and retrieved memory when relevant.

### 9. Tools
When a request genuinely requires external information:
- Use the appropriate web/tool capability;
- Do not fabricate information;
- Keep tool implementation behind the application's provider/service abstraction.

### 10. Voice
Voice interaction is a first-class feature.
Preserve:
- Speech input;
- Automatic send after appropriate silence;
- Text-field clearing after successful send;
- Interruption/stop functionality;
- Streaming or natural response behaviour where supported;
- Human-sounding voice output.
- Never remove voice functionality while fixing unrelated features.

### 11. Image / Vision
The application supports image understanding and image generation.
- Keep image-generation functionality separate from ordinary text responses.
- When an image-generation request is detected: invoke the configured image-generation pathway; return the generated asset to the conversation; do not merely describe the requested image as text.
- Uploaded/taken images must be processed as multimodal input when appropriate.

### 12. Music
Music/song generation is a supported capability.
- Keep generated audio files persistent and associated with the conversation/music library.
- Do not read generated song lyrics or song metadata aloud when the audio itself has already been posted to the conversation.

### 13. Regression Control
Before changing shared code:
- Determine what other features depend on it.
- After changing it, verify at minimum:
  - Text conversation
  - Voice input
  - Voice output
  - Image generation
  - Image upload/vision
  - Character switching
  - Memory retrieval
  - Scrolling
  - Stop/interruption
  - Generated audio
  - Persistence after restart.

### 14. Code Quality
Prefer:
- Small focused changes;
- Existing project patterns;
- Reusable services;
- Clear interfaces;
- Strong typing;
- Defensive error handling;
- Maintainable Flutter/Dart and TypeScript code.
- Do not introduce unnecessary packages.
- Do not duplicate existing services.
- Do not silently change API contracts.

### 15. Workflow
For every task use:
- STEP 1 — Inspect: Understand the current implementation.
- STEP 2 — Diagnose: Identify the actual cause rather than treating symptoms.
- STEP 3 — Plan: Describe the smallest safe implementation.
- STEP 4 — Implement: Modify only the necessary files.
- STEP 5 — Test: Run analyzer/tests/build checks.
- STEP 6 — Preview: Verify the affected UI behaviour.
- STEP 7 — Regression check: Check related functionality.
- STEP 8 — Report: Report files changed, what changed, tests performed, remaining warnings/errors, and anything requiring manual testing.

### 16. Important
- Never make broad architectural changes without explaining why.
- Never replace working code with a speculative implementation.
- Never claim a test passed unless it actually ran.
- When uncertain, inspect the repository before making assumptions.
