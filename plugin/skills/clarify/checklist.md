# Clarify checklist

Run every lens. Most produce nothing on a given ticket. That is fine, and it is better than inventing a question.

## Scope and intent
- Who is the user, and what are they trying to get done? Does the ticket say why, or only what?
- Is anything named but not defined: "admin", "recent", "real-time", "fast", "similar to X", "etc."?
- Does the title contradict the description, an older comment, a linked ticket or the design?
- Is there an implicit second feature, for example "and notify them", "export" or "filter by any field"?
- What is out of scope? If nobody said, write your assumption down.

## Data and rules
- Limits: max length, max count, page size, file size, rate. Are the units stated (°C/°F, kWh, ms)?
- Precision and rounding, currency, time zone (stored, shown, the user's or the site's), locale and date format.
- Empty, zero, null, negative, duplicate, very long text, non-Latin text.
- State machine: which statuses exist, which moves are allowed, who can make each move, and what happens to
  in-flight items when the status changes.
- Source of each value: user input, server, device or third party. When two disagree, which one wins?
- Retention, deletion, audit: is it soft or hard delete, and who can see history?

## Permissions
- Which roles can see, create, change and delete? Is it scoped by tenant, site or ownership?
- What does a user without access see: hidden, disabled with a reason, or a 403 page?

## Failure and time
- Network failure, a timeout, a partial success, a retry. Is the action idempotent?
- Two users editing the same thing; a stale tab; a double click.
- Live data:
  - a source that goes quiet, reconnects or reports late;
  - data that arrives out of order, or carries clocks that disagree;
  - what the screen shows for "no data yet", "stale" and "offline".
- Long-running work: progress, cancel, what happens on page reload.

## Contract
- Every field the UI shows: does the API return it today? If not, who adds it?
- Are error shapes and codes for each failure the UI must tell apart defined?
- Does it break an existing consumer, such as another app, a mobile client, a device or an export?

## Design and UX
- Every state per screen: loading, empty, error, partial, offline or stale, no permission, long text, many items.
  Note which frames are missing.
- Every control's states: hover, focus, pressed, disabled, pending and success/error. This is the `/sdw:ui-polish` inventory.
- Destructive actions: is there a confirm, an undo, or both? Is the consequence stated in the UI copy?
- Copy: are the error, empty-state and confirmation texts written, or is there placeholder lorem?
- Widths: is there a mobile and tablet frame? How does a table, chart or long label collapse?
- Consistency: does it follow the design system's component, or a new look-alike? A new pattern for a solved
  problem is a question for the designer.
- Accessibility:
  - contrast;
  - focus order;
  - meaning carried by colour only (status dots, chart series);
  - target size under 24×24 px;
  - a value that updates live without a pause.
- Heuristics (Nielsen): does the user always know what state they are in? Can they recover from a mistake? Is there a
  shortcut to the frequent action? Does it match what users already know from similar screens?

## Delivery
- Acceptance: how will the PO decide it is done? Is the demo data the real shape?
- Rollout: does it need a feature flag, migration order, a device firmware version, or backfill?
- Dependencies: is another team's work, an access request or a third-party account needed before you start?
