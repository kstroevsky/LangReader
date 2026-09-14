# LangReader Redesign Architecture Specification

## Goal

Modernize LangReader's visual hierarchy, interaction model, navigation, and component system without unnecessarily rewriting its proven document, vocabulary, notes, AI, persistence, or speech architecture.

The redesign changes presentation intentionally and application semantics only when a feature specification explicitly requires it.

## Fundamental Rule

A visual redesign is not authorization to redesign domain ownership.

Existing domain models, workflows, persistence formats, native-reader engines, cancellation semantics, and stable identifiers remain unchanged unless the relevant feature specification explicitly changes them.

---

## Presentation Architecture

Use SwiftUI for ordinary declarative application presentation where it improves composition and iteration.

Keep AppKit or native frameworks where they provide materially better behavior or are already the correct specialized engine, including where appropriate:

* PDFKit document rendering;
* WebKit EPUB/DOCX rendering;
* attributed-text editing through AppKit;
* specialized macOS window/responder behavior;
* performance-sensitive existing native views.

Do not migrate a component to SwiftUI solely because the surrounding redesign uses SwiftUI.

Do not migrate a component to AppKit solely to avoid creating a proper SwiftUI state boundary.

Choose the tool according to behavior, lifecycle, and performance.

---

## Native View Lifetime

`PDFView`, `WKWebView`, rich text editors, and other expensive stateful native views should be long-lived.

A presentation refresh must not recreate a document renderer merely because:

* theme changed;
* sidebar opened;
* toolbar changed;
* another panel updated;
* unrelated observable state changed.

SwiftUI representables must preserve native object identity when the user-visible object is logically the same.

---

## State and Intent

Every redesigned surface must declare a state/action contract before implementation.

For each visible value record:

* authoritative source;
* whether it is domain or presentation state;
* whether it is derived;
* whether it persists.

For each user action record:

* intent;
* owner receiving the intent;
* possible asynchronous work;
* resulting state transition.

Views display state and emit intent.

Do not create a new global redesign ViewModel containing unrelated Reader Shell, Vocabulary, Notes, AI, Search, and Read Aloud state.

Prefer feature- or surface-owned observable state with narrow observation boundaries.

---

## Design System

New presentation code must use semantic design roles rather than local visual constants.

The design system must define at least:

### Color

Semantic roles such as:

* canvas;
* surface;
* elevated surface;
* primary text;
* secondary text;
* tertiary text;
* border;
* separator;
* accent;
* destructive;
* warning;
* success;
* selection;
* hover;
* pressed;
* disabled;
* focus.

Roles must resolve correctly for every supported Reader theme.

### Typography

Define semantic roles rather than arbitrary point sizes:

* display;
* screen title;
* section title;
* body;
* emphasized body;
* secondary body;
* caption;
* metadata;
* control label;
* monospace/code where required.

### Spacing

Define a small spacing scale and use semantic composition instead of unrelated numeric literals.

### Geometry

Define:

* control heights;
* icon sizes;
* corner radii;
* panel padding;
* row density;
* minimum touch/click targets;
* divider geometry.

### Motion

Define:

* standard duration classes;
* easing;
* panel transitions;
* hover/press transitions;
* reduced-motion behavior.

Animation must communicate state or spatial relationship rather than decorate ordinary operations.

---

## Reusable Components

Create a shared component only when:

* the same semantic control appears in multiple real surfaces; or
* centralizing it is necessary to guarantee an interaction/accessibility/design invariant.

Do not create a generic component framework in anticipation of possible future reuse.

A component abstraction should describe a semantic role, not merely a visual shape.

Prefer names such as `ReaderPanelHeader` over `RoundedHStackContainer`.

---

## Feature Boundaries

Visual containment does not automatically imply architectural ownership.

A sidebar containing Search, Notes and Vocabulary controls does not become the owner of Search, Notes and Vocabulary state.

The surface composes feature projections and routes intents to the existing feature owners.

---

## Native Reader Interaction

New UI must never obtain direct `PDFView` or `WKWebView` access just because a button needs to affect the document.

Use existing semantic reader backends or introduce a narrow typed capability.

Examples:

* navigate to page;
* change zoom;
* obtain semantic selection;
* reveal saved occurrence;
* request search;
* reveal source location.

Do not expose the renderer itself to make UI implementation easier.

---

## Redesign State Matrix

Every redesigned surface must define and visually validate applicable states:

* normal;
* hover;
* pressed;
* focused;
* selected;
* disabled;
* empty;
* loading;
* partial loading;
* error;
* cancellation;
* no document;
* unsupported format;
* restored session;
* light/original theme;
* eye-care theme;
* dark theme.

An AI-generated mockup showing only the ideal populated state is not an implementation specification.

---

## Window and Layout Behavior

Specify behavior at least for:

* minimum supported window size;
* typical window size;
* wide window;
* panel open/closed states;
* long localized strings;
* large Dynamic Type/accessibility-equivalent text where relevant;
* long document titles and metadata.

Important controls must not depend on one screenshot's dimensions.

---

## Keyboard and macOS Behavior

The redesign must preserve or intentionally redefine:

* first responder behavior;
* keyboard shortcuts;
* tab/focus traversal;
* Escape handling;
* Return/Space activation where appropriate;
* arrow/page navigation;
* text-selection behavior;
* contextual menus;
* window dragging;
* accessibility identifiers used by tests.

macOS-native interaction behavior is part of the product contract, not incidental implementation detail.

---

## Accessibility

Every new interactive component must have:

* meaningful accessibility role;
* label where visual content is insufficient;
* state/value exposure where applicable;
* keyboard accessibility;
* sufficient target size;
* theme-appropriate contrast;
* distinguishable focus.

Do not communicate state solely through color.

---

## Performance

Redesign work must not widen observation invalidation unnecessarily.

Avoid:

* one observable object driving the entire app;
* publishing scroll position on every pixel to unrelated views;
* rebuilding large attributed strings during unrelated updates;
* rerendering long AI conversations because toolbar state changed;
* resampling document thumbnails synchronously during scrolling;
* performing document parsing, database work, embeddings, Markdown transformation, or hashing in SwiftUI view evaluation.

Batch or throttle high-frequency state where exact frame-by-frame propagation is unnecessary.

Cache expensive derived presentation when invalidation can be stated precisely.

---

## Visual Verification

Every meaningful redesigned surface must be inspected in the real application.

For major surfaces capture representative states after implementation.

Visual verification must cover the dimensions that matter to that feature, for example:

* normal populated state;
* empty state;
* loading/error state;
* dark/eye-care theme;
* narrow window;
* selected/focused state.

A successful build is not proof that a redesign is correct.

---

## Redesign Decomposition

Treat the overall redesign as a roadmap rather than one implementation feature.

Each major product surface receives its own:

* `spec.md`;
* `design.md`;
* `tasks.md`;
* convergence review.

The redesign roadmap owns only cross-surface decisions such as:

* information architecture;
* navigation model;
* design system;
* shared interaction patterns;
* rollout order.

Sub-features own their concrete state and implementation.

---

## Architecture Gate for Every Redesigned Screen

Before implementation answer:

1. Which existing feature owns each displayed state?
2. Which object receives each user intent?
3. Which state is presentation-only?
4. Does anything new persist?
5. Does this touch PDFKit/WebKit?
6. Can an existing reader capability express the required operation?
7. What native objects must retain identity?
8. Which semantic design tokens/components are used?
9. What are the empty/loading/error/focus states?
10. What keyboard and accessibility behavior must survive?
11. What high-frequency events exist?
12. How will the rendered result be verified?

Do not implement the screen until these answers are coherent.

---

## Forbidden Redesign Shortcuts

Do not:

* duplicate domain state into a redesign ViewModel;
* make labels/text fields authoritative data stores;
* access databases directly from views;
* access `PDFView`/`WKWebView` directly from new presentation code;
* store native selection geometry as cross-feature domain state;
* create raw-JavaScript escape hatches;
* introduce hard-coded one-off palette values when a semantic role exists;
* create arbitrary spacing/radius values for each screen;
* recreate expensive native views due to ordinary SwiftUI invalidation;
* rewrite working domain services merely to fit a new component hierarchy;
* create generic abstractions with no concrete second use or testability benefit;
* change persisted formats accidentally as part of visual work.
