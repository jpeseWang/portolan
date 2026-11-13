# Slack question draft

One message per person. Plain English, written for someone reading it on their phone between meetings.

```
Hi <name>, a few questions on <KEY>: <title> (<ticket link>) before I build it.
<n> of them block me; for the rest I'll go with the suggested option if I don't hear back by <day>.

1. *<short title>* (blocks <the feature part, in their words>)
   <one line of context> (<link to the spec section or design node>)
   A) <option> → <consequence>
   B) <option> → <consequence>
   I'd suggest A: <reason>.

2. *<short title>*
   …

Replying "1A, 2B" in the thread is enough. Thanks!
```

## Rules
- Put blockers first. Keep it to 7 questions or fewer. Each one can be answered with a letter, or with a short value ("max 500").
- Use their vocabulary, not ours. Write "the export button", not "AC-2". Don't mention local file paths, sdw, lanes or tools.
- Link to the ticket, the spec section and the design node, so they never have to search.
- Give a deadline only for non-blocking questions, and make it real: the day you will build the default.
- For a contradiction between two sources, quote both briefly, mention the other owner, and ask the person who decides.
- Where to post:
  - in the ticket's existing thread or the project channel, so the decision can be found later;
  - by DM only when people.md says that person prefers it, or when the question is sensitive (security, a person, money).
- If an answer arrives in a call or a DM, post a one-line summary in the thread ("Agreed with <name>: …") so the
  record stays public. Draft that line too.
- Never @channel or @here. Never ping someone outside their working hours (people.md TZ) unless the question
  blocks a release.
