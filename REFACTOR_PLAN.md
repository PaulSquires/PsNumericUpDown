# CNumericUpDown — design record

Why this control is shaped the way it is. The `README.md` says how to use it; this says what
was decided, what was rejected, and what it cost.

## The brief

A spinner matching a reference screenshot: a rounded dark cell holding `−  16.00  +` with thin
vertical dividers between the three parts. Host-supplied colours and font. Callbacks for
message processing and painting. No tooltips. `isHot` / `isFocused` (a real tabstop) /
`isDisabled`. A user-defined number of decimal places and a user-defined increment.

## The decisions

Taken deliberately, in an interview before any code was written. Recorded so they are not
re-litigated.

### 1. The value field is a real editing control, not drawn text

Three options were on the table: a fully owner-drawn control that only the buttons can change,
an embedded `CTextBox`, or hand-rolled inline editing.

**Chosen: embed a `CTextBox`.** Reading its source first is what made the choice cheap —
nearly everything an editable numeric field needs is already there:

| what | where |
|---|---|
| the numeric grammar, typed *and pasted* | `CTextBox.inc` `WM_CHAR` / `WM_PASTE` |
| decimal places + reformat on focus loss | `CTextBox.inc:1122-1135`, via an internal `WM_SETTEXT`, **before** the `FocusCallback` fires |
| `GetValue` / `SetValue` as a `double` | `CTextBox_GetValue` / `SetValue`, silent |
| a message callback with veto | `CTextBox.inc:923-926` — hands over `WM_KEYDOWN`, `WM_CHAR`, `WM_MOUSEWHEEL`, the mouse buttons and the focus pair *before* acting |
| select-on-focus, applied synchronously | `CTextBox.inc:1141-1150` |
| Tab without `IsDialogMessage` | `CTextBox.inc:1068-1081`, `GetAncestor(GA_ROOT)` + `GetNextDlgTabItem` |

Hand-rolling inline editing would have meant a caret, selection painting, IME, and the
clipboard — nothing in the family has ever done that, and it would have been by far the most
code and the most to get wrong. A display-only control was the cheapest option but a real loss:
a user who knows they want 42 should be able to type 42.

**The cost, stated honestly:** three vendored files instead of one, a mandatory message-pump
call, and focus that lives two levels down so `GetFocus() = hCtrl` is never true.

### 2. Centring the number: upstream, after the cheap route turned out not to work at all

CTextBox had **no alignment API** — its text was left-aligned against the margin. The first
version of this control took the cheap route: `EM_SETPARAFORMAT` / `PFA_CENTER` sent straight
at the RichEdit through `CTextBox_GetRichEditHandle`, the escape hatch CTextBox documents for
precisely this. Adding a setter upstream was rejected as a second piece of work riding along.

**That was wrong, and not for the reason the trade-off was argued over.** The escape-hatch
version *did not work*. `TM_PLAINTEXT` — which CTextBox uses to keep one character format
across the buffer and to make pasted text shed its rich formatting — **refuses
`EM_SETPARAFORMAT` outright**. The message returned failure every single time, the alignment
stayed `PFA_LEFT`, and nothing anywhere reported a problem. The number was never centred.

It shipped in the first commit, correctly flagged as the highest-risk unverified item, and
survived because the control had no way to check its own work. What exposed it was a single
assertion in CTextBox's harness that **asked the RichEdit** what its paragraph format actually
was, instead of trusting a stored field. Measured, then, rather than reasoned about:

| sequence | `EM_SETPARAFORMAT` returns | resulting alignment |
|---|---|---|
| under `TM_PLAINTEXT`, single-line | 0 (failure) | `PFA_LEFT` |
| under `TM_PLAINTEXT`, multiline | 0 (failure) | `PFA_LEFT` |
| under `TM_PLAINTEXT`, after select-all | 0 (failure) | `PFA_LEFT` |
| under `TM_RICHTEXT` | 1 (success) | `PFA_CENTER` — **and it survives the switch back to plain text, and every later `SetText`** |

So the upstream setter was added after all, and it is built around that last row: empty the
buffer, flip to rich-text mode, apply, flip back, restore. `CNumericUpDown` calls it once at
Create, while the buffer is still empty, which is when that dance costs nothing.

**The generalisable lesson**, and the reason this entry is this long: the escape hatch was a
sanctioned, documented mechanism, and using it was a defensible call. What made the outcome
bad was not the choice — it was shipping a *silent* mechanism with no assertion behind it.
A `SendMessage` whose return value is discarded is an assumption, not an implementation.

### 3. Typing notifies on commit, not per keystroke

Buttons, arrows and the wheel each produce a complete value and notify immediately. Typing
notifies on ENTER or focus loss, which is also when the value is clamped and reformatted.

Per-keystroke notification would report the transient `1` while `16` is being typed, and an
empty field as `0`, and every host would then have to filter it back out. A separate live
`EditingCallback` was considered and dropped: two callbacks and two contracts for a case no
host has asked for yet.

### 4. Focus is a border colour, not a ring

`CToggle` reserves a ring band on all four sides, unconditionally, so the pill never jumps when
focus arrives. That is the right answer for a small pill floating in a settings row and the
wrong one here: this control *looks like* a text field, and a text field lights its border —
CTextBox's own `SetFocusBorderColor` is the precedent. It also means the ideal size is the same
focused or not, with no empty band to pay for.

### 5. The cells are not deflated by the border

The first implementation deflated every cell by the border thickness, which is the obvious
reading of "the border goes around the outside". **It is wrong here**, and the geometry
self-test caught it on the first run (four failures).

The button cells have to reach the frame's rounded corners. A cell inset by the border width
rounds its own corners a pixel inside the frame's, leaving a sliver of the base fill showing
through wherever a hovered button's colour differs from it. So the cells span the full client
and the border is stroked over their outer edges, last.

`rcValue` alone is inset vertically, by exactly the border thickness, and for a completely
different reason: the child window covers every pixel of that rect and paints its own
background there, so a full-height value cell would put the child on top of the frame's top and
bottom rows and the border would be interrupted across the middle of the control. Nothing else
is covered by a child, so nothing else needs the inset.

### 6. Stepping on the button-down, and what that does to the capture rationale

The plan for this control inherited the family's press/cancel wording — press, slide off,
release, nothing happens. **That is not what a spinner does, and implementing it would have
been wrong.** A spinner steps on the button-down, because auto-repeat has to start somewhere
and a first step deferred to the release would arrive *after* the repeats it precedes.

Capture is still taken, and the family's full price is still paid (release before any callback
runs, `WM_CAPTURECHANGED` cancels, `WM_DESTROY` releases, no callback may suppress the
up-message). But it buys something different here: the repeat stops the moment the cursor
leaves the button and resumes — after the full delay again, so a wobbling cursor cannot
machine-gun the value — if it comes back, and the up-message is guaranteed to arrive wherever
the cursor has wandered to, so the repeat timer can never outlive the gesture.

This is the trap CLAUDE.md warns about when a control is seeded from a sibling: *"a 'no
capture' note copied into a new control is an assumption to re-test, not a law to inherit"* —
and the same applies to a *reason* for capture.

### 7. A button click focuses without selecting

Select-on-focus is on, so tabbing in highlights the number and the first keystroke replaces it.
Applying that uniformly would leave `17.00` highlighted after every click of `+`, which reads
as noise.

The fix is to toggle CTextBox's flag off around the `SetFocus` and back on immediately. That is
safe rather than a timing gamble because CTextBox applies select-on-focus **synchronously**
inside its `WM_SETFOCUS` handler — the whole effect is over before `SetFocus` returns. A field
tracking "suppress this" was written first and then deleted: nothing ever read it, because the
toggle already carries the state for exactly the window in which it matters.

### 8. Glyphs are drawn geometry

Filled rectangles through `CBufferPaint`: one bar for `−`, two crossed bars for `+`. Not a
glyph font (CIconPanel's approach), which would make the control depend on Segoe Fluent Icons
being installed and need per-size optical tuning; and not host-supplied text, which pushes that
tuning onto every host.

Learnings.md is explicit that axis-aligned rules render squarer as filled rectangles than as
lines or an antialiased 1px pen — a stated extent sidesteps both the smoothing and the
endpoint-inclusion question. The same reasoning covers the dividers.

Both `+` bars are centred on the *same* cell centre rather than one being derived from the
other, so the cross is symmetric whatever the parity of the cell and the bar.

### 9. Range clamps, never wraps

A font size stepping from 72 straight to 6 is a bug, not a feature. Wrap would be right for
cyclic values (hours, angles) and can be added behind a flag if one ever turns up.

The button that can do nothing at a limit is painted disabled — the only per-part state in the
renderer — and auto-repeat stops dead there rather than spinning against the clamp.

### 10. Every step is snapped to the decimal grid

Not merely formatted for display. Adding 0.1 ten times to a binary double lands on
0.9999999999999999; a value a hair below the grid *formats correctly while comparing wrong*, so
the drift stays invisible until a range check disagrees with the number on screen. The
self-test asserts the exact case.

The paired decision: "did the value change" is answered against a quarter of a grid unit rather
than a fixed epsilon, which keeps it correct at 0 decimal places as well as at 4.

### 11. Home and End are not claimed

Up/Down and PgUp/PgDn are free to take — a single-line RichEdit does nothing useful with them.
Home and End are not: they move the caret to the start and end of the text, and stealing them
for min/max would break ordinary editing in a field the user can type into.

## What was rejected

| Rejected | Why |
|---|---|
| a stacked up/down arrow layout | one layout, one geometry routine, one set of assertions. Addable later without changing the API shape |
| suppressing CTextBox's context menu | it would have removed the pump obligation and one vendored pair, but paste into a numeric field is genuinely useful and CTextBox already validates pasted text |
| accelerating auto-repeat | a fixed rate is enough for the ranges this control is for; the curve is state and assertions for no asked-for gain |
| a host-sizes-it-entirely model | the host would have to guess a width that fits its numbers, and a too-narrow control clips silently |
| thousands separators, prefix/suffix | the field's grammar and the ideal-size measurement would both have to learn about them |
| reusing CTextBox's private `CTextBox_FormatNumeric` | everything is textually included into one module so it happens to be reachable, but reaching for it would couple this control to an implementation detail of a file that is *synced from elsewhere* |

## Verification, and its limits

- Builds clean with `-w all`, zero warnings.
- `CNUMERICUPDOWN_SELFTEST=1` — **54 assertions, 0 failed**. Geometry at a comfortable size and
  at one too narrow to fit; cells and dividers tiling the client exactly; glyph centring and
  cross symmetry; the child positioned exactly on `rcValue`; a hit-test round trip over every
  part; `GetIdealSize` against an independently measured oracle (the widest formatted value at
  *both* ends of the range, in the same font); the decimal-grid arithmetic; clamping at both
  limits; every programmatic setter proven silent; the wheel's sub-notch accumulation crossing
  a 120 boundary; enable/disable reaching both windows; read-only reaching the child.
- The first run failed 5 of 48 — four from the border-deflation bug above, one from a wrong
  expectation in the test itself (`-50.00` is *not* wider than `1000.00`; the range was changed
  to one where the minimum genuinely is the wider string, so the assertion is load-bearing).

**Not verified, and it is a real gap:** nothing interactive. Hover, the pressed look,
auto-repeat, Tab through the two container levels, select-on-focus versus
caret-on-button-click, typing and its commit, and the right-click menu. That is the author's
pass. Learnings.md is explicit that a
`SendMessage`-simulated click cannot reproduce mouse capture, so no attempt is made to fake
one; the wheel *is* driven by a real message, because a hover-wheel genuinely arrives that way.

**Centring is no longer on that list.** It was the single highest-risk item, and it turned out
to be broken (see decision 2). It is now asserted three ways — the alignment round-trips
through `CTextBox_GetTextAlign`, the RichEdit itself reports `PFA_CENTER` when asked directly,
and it still reports `PFA_CENTER` after a value change rewrites the buffer. What is left on
the interactive list is genuinely visual: whether the centred number *looks* right between the
margins, not whether it is centred at all.

## If this is ever folded into a host

Nothing in the workspace uses it yet. When something does:

1. Add `CNumericUpDown_FilterMessage` to the pump. An app already hosting CTextBox or CMenuBar
   is calling a sibling filter already; they are independent and each stands down while the
   other's menu is up.
2. Vendor `CBufferPaint`, `CPopupMenu` and `CTextBox` from their canonical repos, not from
   here — this repo's copies are themselves vendored.
3. `AfxGdipInit` / `AfxGdipShutdown` must bracket the message loop, and **nothing may be named
   `ok`**: GDI+'s `Status` enum defines `Ok = 0` in namespace `AfxNova`, and every host says
   `using AfxNova`. The family convention is `bOK`.
