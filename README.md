# CNumericUpDown

A reusable owner-drawn **numeric up/down** (spinner) for FreeBASIC / Win32: a rounded frame
holding a `−` button, an **editable** numeric field and a `+` button, separated by hairline
dividers.

```
┌───┬──────────┬───┐
│ − │  16.00   │ + │
└───┴──────────┴───┘
```

The thirteenth control in the family (`CListBox`, `CVScrollBar`, `CHScrollBar`, `CStatusBar`,
`CTabBar`, `CTextBox`, `CMenuBar`, `CPopupMenu`, `CSplitter`, `CIconPanel`, `CSelectBar`,
`CToggle`), and it follows the same template: one real `HWND`, per-instance state in a `TYPE`
in the `CWindow` UserData area, one `WndProc`, host callbacks for painting and messages, one
`CBufferPaint` per `WM_PAINT`, no host globals, rects derived and never set, programmatic
setters silent.

**It is the third control that wraps a real child** (after `CListBox` and `CTextBox`), and the
second that is focusable (after `CToggle`).

## Files

| File | Role |
|---|---|
| `CNumericUpDown.bi` | the control: defines, `NUD_*` enums, colours, paint/message info, callback typedefs, the `CNUMERICUPDOWN` type, `LayoutControl`, and the documented public API |
| `CNumericUpDown.inc` | implementation: the built-in painter, the `WndProc`, `Create`, the three CTextBox hooks, and the API bodies |
| `CTextBox.bi/.inc`, `CPopupMenu.bi/.inc`, `CBufferPaint.bi/.inc` | vendored copies, synced from their canonical repos — **do not edit them here** |
| `main.bas`, `frmMain.bi/.inc` | demo harness — a settings pane of six spinners plus a plain CTextBox — and the self-test |
| `main.rc`, `main_manifest.xml` | makes the demo DPI-aware. Not optional: measuring a GUI in a DPI-unaware process invalidates the measurement |

Build (the toolchain is not on `PATH`, and AfxNova resolves relative to the workspace root):

```bash
C:\dev\tiko_editor\toolchains\FreeBASIC-1.10.1-winlibs-gcc-9.3.0\fbc64.exe -i "C:\dev" main.bas main.rc
```

or just `build.bat`. Run the self-test with `CNUMERICUPDOWN_SELFTEST=1` — 54 assertions,
geometry and value arithmetic.

Include order — the price of embedding a real editing control:

```freebasic
#include once "CBufferPaint.inc"
#include once "CPopupMenu.inc"
#include once "CTextBox.inc"
#include once "CNumericUpDown.inc"
```

`CNumericUpDown.bi` includes both `CBufferPaint.bi` and `CTextBox.bi` itself, so it names no
type it has not loaded — deliberately unlike `CListBox.bi`, which compiles only at an include
site that has pre-loaded its siblings.

## Quick start

```freebasic
dim as HWND hSpin = CNumericUpDown_Create( hWndParent, IDC_MYSPINNER )

CNumericUpDown_SetFont( hSpin, hMyFont )          ' you keep ownership
CNumericUpDown_SetRange( hSpin, 6.0, 72.0 )
CNumericUpDown_SetValue( hSpin, 16.0 )            ' silent: fires no callback
CNumericUpDown_SetValueChangedCallback( hSpin, @MyValueChanged )

' Size it to what the widest value in the range actually needs.
dim as long iw, ih
CNumericUpDown_GetIdealSize( hSpin, iw, ih )
SetWindowPos( hSpin, 0, x, y, iw, ih, SWP_NOZORDER )
ShowWindow( hSpin, SW_SHOW )
```

```freebasic
sub MyValueChanged( byval hCtrl as HWND, byval nValue as double )
    ' Only user action gets here.
end sub
```

**And one line in your message pump — this is not optional:**

```freebasic
do while GetMessage(@uMsg, null, 0, 0)
    if CNumericUpDown_FilterMessage( @uMsg ) then continue do
    TranslateMessage @uMsg
    DispatchMessage @uMsg
loop
```

See [The host obligation](#the-host-obligation) for why.

## It wraps a real child

The value field is a `CTextBox` in numeric mode, whose own child is a `RichEdit50W`. Typing,
selection, the clipboard, undo, paste validation and the right-click menu all come from there
— none of it is reimplemented.

```
CNumericUpDown container      WS_EX_CONTROLPARENT
  └── CTextBox                borderless: THIS control owns all the chrome
        └── RichEdit50W       WS_TABSTOP — the real focus target
```

What that buys, and what it costs:

| | |
|---|---|
| **Buys** | the numeric grammar (digits, one leading minus, one separator — typed *or pasted*), decimal places with reformat-on-focus-loss, `GetValue`/`SetValue` as a `double`, a caret and a selection, Cut/Copy/Paste/Select All |
| **Costs** | three vendored files instead of one, a message-pump obligation, and focus that lives two levels down |

`CNumericUpDown_GetTextBoxHandle` is the escape hatch — every `CTextBox_*` setter applies to
it (cue banner, limit text, context-menu theming). **Three are owned by this control** and
must not be set behind its back: `CTextBox_SetValue` / `SetDecimalPlaces` (use ours, or the
cached value and the buttons' limit state go stale) and `CTextBox_SetBorderWidth` (nonzero
would draw a second frame inside ours).

### The two gaps embedding creates, and how each is closed

**CTextBox had no alignment API** — its text was left-aligned against the margin, and the
number here is centred. It has one now: `CTextBox_SetTextAlign`, added upstream for this
control and called once at Create, while the buffer is still empty.

That timing is not incidental. Applying alignment **rewrites the CTextBox buffer** and
discards its undo history, because `TM_PLAINTEXT` refuses `EM_SETPARAFORMAT` outright — see
CTextBox's own README. At Create there is nothing to discard.

This replaced an earlier version that sent `EM_SETPARAFORMAT` at the RichEdit directly
through the documented escape hatch. That version **did not work and reported no error**: the
message was refused every single time and the number was never centred. It was written, shipped
in a first commit, and flagged as the highest-risk unverified item — and it took an assertion
that *asked the RichEdit* rather than trusting the control's own stored state to expose it.

**CTextBox has no enabled state.** `CNumericUpDown_SetEnabled` calls `EnableWindow` on the
container **and** on the CTextBox, so the disable is enforced by the system rather than being
a cosmetic flag — disabling only the container would leave the textbox itself enabled and a
programmatic `SetFocus` could still drop a caret into a control that looks dead.

## The layout

Everything derives from the client rect plus a few authored scalars. `LayoutControl()` is the
only producer; painting, the child's placement and every rect query consume it.

```
  rcFrame  = the whole client
  rcMinus  = client.left ..              client.left + nButtonWidth
  rcDiv1   = rcMinus.right ..            + nDividerThick
  rcPlus   = client.right - nButtonWidth .. client.right
  rcDiv2   = rcPlus.left - nDividerThick .. rcPlus.left
  rcValue  = rcDiv1.right ..             rcDiv2.left      ← the CTextBox sits exactly here
```

**The cells are not deflated by the border**, and that is deliberate: the button fills have to
reach the frame's rounded corners, and a cell inset by the border width would round its own
corners a pixel inside the frame's, leaving a sliver of the base fill showing whenever a
hovered button's colour differs from it. The border is stroked *over* the cells' outer edges,
last.

**`rcValue` alone is inset vertically**, by exactly the border thickness. The child covers
every pixel of that rect and paints its own background — a full-height value cell would put
the child on top of the frame's top and bottom rows and the border would be interrupted across
the middle of the control. Nothing else is covered by a child, so nothing else needs it.

Overflow is computed honestly and clipped, never squeezed: too narrow and the value cell
collapses to zero width (the child is hidden rather than handed a degenerate rect) while the
buttons keep their size.

`LayoutControl` takes **no DC** — every number is authored or derived. `GetIdealSize` is the
one place this control measures anything, and it opens its own DC, which is what makes it
valid *before* the control has ever been sized.

All setters take **raw pixels**; the caller DPI-scales. Only the Create-time defaults are
scaled for you. The **border** and **divider** thicknesses are never scaled at all, because a
hairline should stay a hairline — but the **glyph** thickness is, and that asymmetry is
deliberate. Those two are *rules*; the `−` and `+` bars are the strokes of an *icon*, and
scaling an icon's length but not its weight makes it thinner relative to itself at every step
up in DPI. At 1.75× the unscaled version was 18 px long and 1 px thick, which read as a thread
rather than a minus sign.

## Rendering

`CNumericUpDown_RenderDefault` draws through `CBufferPaint`. **The paint order is
load-bearing**, and it is what keeps the corners round:

| # | what | how |
|---|---|---|
| 1 | the client | `PaintClientRect` in `BackColor` — shows through outside the rounded corners |
| 2 | the frame's fill | `PaintRoundRect(rcFrame)` — this is what makes the corners round, and it is also the value cell's background for the strip above and below the child |
| 3 | each button cell | `PaintRoundRect` on the cell **extended inward past the divider**. A plain rectangular fill would square off the two corners it covers; extending it puts its own unwanted inner rounding somewhere harmless |
| 4 | dividers and glyphs | `PaintRect` — filled rectangles, not lines. An antialiased 1px axis-aligned rule comes out grey and blurry, and a stated extent sidesteps both the smoothing and the endpoint-inclusion question |
| 5 | the frame outline | `PaintRoundOutline`, **not** `PaintRoundBorderRect` — a filled round rect here would erase steps 2–4 |

Curvature is a **diameter** in this API (`CBufferPaint` halves it to a GDI+ radius
internally), so the corner radius is doubled at every call site.

**It never draws the number.** The RichEdit paints that over `rcValue` afterwards — and
because the container is `WS_CLIPCHILDREN`, the child's rect is excluded from our DC anyway,
so anything drawn there is discarded rather than fighting for the pixels. A paint callback
replaces the frame, the cells, the dividers and the glyphs; it does not and cannot replace the
value.

## Colours

`CNUMERICUPDOWN_COLORS` is a flat struct of `COLORREF` fields with defaults. Read-modify-write
is Get, assign, Set.

**The control reads as one flat cell until you hover a button**, because `ButtonBackColor`
defaults *equal to* `ValueBackColor` — CSelectBar's trick applied the other way round, and it
is what makes the dividers the only thing separating the three parts at rest. A host that
wants visibly raised buttons just sets the field.

The value cell's two colours live in this struct but are pushed into the CTextBox, because the
RichEdit draws the number. That bridge is the only reason a host does not have to set colours
in two places.

## Value behaviour

| | |
|---|---|
| **Range** | `SetRange(min, max)`, clamping, no wrap. An inverted pair is swapped rather than accepted |
| **At a limit** | the button that can do nothing is painted disabled, and auto-repeat stops dead there |
| **Decimal grid** | every step is snapped back onto the decimal grid, not merely formatted for display. Adding 0.1 ten times to a binary double lands on 0.9999999999999999 — a value a hair below the grid formats correctly while comparing wrong, so the drift stays invisible until a range check disagrees with the number on screen |
| **Increments** | added, never snapped to a multiple of the increment (classic spinner behaviour) |
| **Empty** | reads as 0 and is then clamped into the range, so the control can never be left blank. There is no "no value" state |

### When the change callback fires

**Immediately** for a button click, an auto-repeat tick, an arrow key, PgUp/PgDn and the wheel
— each of those produces a complete value.

**On commit only** for typing: ENTER, or focus leaving the field, which is also when the typed
text is clamped and reformatted. Typing `16` therefore never reports the transient `1`.

**Never** for `SetValue`, `SetRange`, `SetDecimalPlaces`, `StepUp` or `StepDown`. They are
programmatic setters, which is Win32's own `BM_SETCHECK`/`BN_CLICKED` split and what makes it
safe to call one from inside the handler.

## Focus and keyboard

- Focus sits on the RichEdit two levels down, so `GetFocus() = hCtrl` is **always** false —
  use `CNumericUpDown_HasFocus()`.
- The frame recolours to `FocusBorderColor`. There is no separate focus ring and therefore no
  reserved band, so the ideal size does not change when focus arrives.
- **Tab navigation works without `IsDialogMessage`**, because CTextBox handles `VK_TAB` itself
  by walking `GetAncestor(GA_ROOT)` + `GetNextDlgTabItem`. That walk only sees through a
  container that declares itself one, which is why this control's container carries
  `WS_EX_CONTROLPARENT` — it is load-bearing, not decoration. The demo deliberately omits
  `IsDialogMessage` from its pump to prove it.
- **Tab in and the number is selected**, so the first keystroke replaces it. **A button click
  focuses the field without selecting**, placing the caret instead — otherwise every click of
  `+` would leave the number highlighted. Toggling CTextBox's flag around the `SetFocus` is
  safe rather than a timing gamble, because CTextBox applies select-on-focus synchronously
  inside its own `WM_SETFOCUS`.
- **Up/Down** step by the increment, **PgUp/PgDn** by the large increment. They are free to
  claim: a single-line RichEdit does nothing useful with them.
- **Home and End are deliberately not claimed.** They move the caret to the start and end of
  the text, and stealing them for min/max would break ordinary editing in a field the user can
  type into.
- **The wheel** steps one increment per notch, accumulating sub-notch deltas so a slow
  trackpad swipe is not ignored. `SPI_GETWHEELSCROLLLINES` is deliberately *not* consulted,
  which is where this parts company with the scrollbars: "how many lines does one notch
  scroll" is a question about a view, and this is a value.

## Callbacks

| Callback | Fires |
|---|---|
| `NUD_ValueChangedCallbackSub` | the **user** changed the value — see the table above |
| `NUD_MessageCallbackFunc` | mouse, timer, key, wheel and focus messages. Return TRUE to suppress default handling |
| `NUD_PaintCallbackSub` | draw the frame, cells, dividers and glyphs instead of the built-in painter |

**Two sources feed one message callback.** The container's own messages (the mouse over the
buttons, the timers, enable/disable) arrive directly; the value field's key, wheel and focus
messages arrive relayed from the embedded CTextBox with the handle rewritten to *this*
control. A host sees one message stream and never has to know a RichEdit is in there.

**The result is IGNORED for two messages.** `WM_LBUTTONUP`, because the control holds capture
across a button press and the up-message is what releases it — suppressing it would strand
capture. `WM_KILLFOCUS`, because focus loss is what *commits* a typed value, and a suppressed
commit would leave the control displaying a number it has not accepted.

## The host obligation

The value field carries CTextBox's built-in right-click Cut/Copy/Paste/Select All menu, which
is a **CPopupMenu** and therefore not modal: keyboard navigation and click-outside dismissal
both live in a message filter. A host that never calls `CNumericUpDown_FilterMessage` gets a
menu that opens and paints but cannot be driven from the keyboard and never closes on an
outside click.

It forwards to `CTextBox_FilterMessage`, so an app already calling that is covered either way
and calling both is harmless. It exists so a host adopting this control has **one** call to
add rather than having to know there is a CTextBox inside it with a CPopupMenu inside that.

### One trap when writing a paint callback

Draw the frame with **`PaintRoundOutline`** (curvature 0 for square corners), never
`PaintBorderRect` or `PaintRoundBorderRect`. Those delegate to `PaintRectFactory`, which
**fills the rect with the current back colour unconditionally** — the fill is not gated on
anything, only the stroke is. Used for a frame, over pixels you have just drawn, it floods the
whole control with whatever colour you last set and erases the cells, the dividers and the
glyphs, leaving a solid block with only the value showing through.

Nothing reports an error, and every geometry assertion still passes. This exact defect has now
been written three times in this control family (`CComboBox`, `CToggle`, and the demo callback
here), every time by copying a sibling's paint callback without re-checking it.
`SelfTest_MinusCellTones` asserts against it: it drives the demo's callback into an offscreen
buffer and counts colours inside the minus cell, where **one** colour means flooded.

The same shape bites anything drawn *over* existing pixels, not just the frame.

## Two traps worth knowing

**Capture is taken, but not for the reason its siblings take it.** A spinner **steps on the
button-down**, not on the release — it has to, because auto-repeat has to start somewhere and
a first step deferred to the release would arrive after the repeats it precedes. So sliding
off a button does *not* undo the step that already happened; this is not the press/cancel
gesture `CToggle` and `CSelectBar` implement. What capture buys here is that the repeat stops
the moment the cursor leaves the button (and resumes, after the full delay, if it comes back),
and that the up-message is guaranteed to arrive wherever the cursor has wandered to, so the
repeat timer can never outlive the gesture. Every real spinner behaves this way.

**`CS_DBLCLKS` is deliberately NOT set** — CToggle's and CIconPanel's call rather than
CSelectBar's. With it, the second of two rapid clicks arrives as `WM_LBUTTONDBLCLK` *instead
of* a second `WM_LBUTTONDOWN`, and a user double-clicking `+` to add two would get one.

## Not implemented, deliberately

- **No wrap-around.** A font size stepping from 72 straight to 6 is a bug, not a feature.
- **No thousands separator and no prefix/suffix text.** The field's grammar and the ideal-size
  measurement would both have to learn about them.
- **No stacked up/down arrows.** One layout, one geometry routine, one set of assertions. A
  second style can be added later without changing the API shape.
- **No tooltips**, no animation, and **no tri-state**.
- **No `CNumericUpDown_SetValueSilently` distinction** — every setter here is already silent.

## Verification

- Builds clean with `-w all`, zero warnings.
- `CNUMERICUPDOWN_SELFTEST=1` — 54 assertions, all passing: every rect at a comfortable size
  and at one too narrow to fit, the cells and dividers tiling the client exactly, the glyph
  bars centred and the `+` cross symmetric, the child positioned exactly on `rcValue`, a
  hit-test round trip over every part, `GetIdealSize` against an independently measured
  oracle, the decimal-grid arithmetic, clamping at both limits, every programmatic setter
  proven silent, and the wheel's sub-notch accumulation crossing a 120 boundary.
- **The interactive pass has been run and passed** (2026-07-23, by the author): hover, the
  pressed look, auto-repeat, Tab navigation through the two container levels, select-on-focus
  versus caret-on-button-click, typing and its commit, the right-click menu, and the centred
  number's appearance between its margins. That the number **is** centred is asserted three
  ways, including by asking the RichEdit — but whether it *looks* right was never anything an
  assertion could answer.

  It matters more here than in a typical control, because two of the three defects found in
  this one were invisible to every assertion that looked at numbers: an `EM_SETPARAFORMAT`
  that was refused in silence, and a paint callback that flooded the control with a single
  colour. Both now have assertions; neither had one when it shipped.

  No attempt is made to fake a click — a `SendMessage`-simulated click cannot reproduce mouse
  capture, so it would prove nothing. The wheel *is* driven by a real message, because a
  hover-wheel genuinely arrives that way.
