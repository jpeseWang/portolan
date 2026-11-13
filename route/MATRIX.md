# Model matrix

Default choices. `aim-pick <role>` applies them against your current quota; edit `routing.json` to change them.

| Task | Tool | Model |
|---|---|---|
| Architecture, hard debug, security review, migrations | `claude` / `codex` | Opus / top GPT |
| Normal feature work, refactor | `claude` | Sonnet |
| Boilerplate, rename, simple tests, i18n, summarising code | `claude-ds` (optional) | ds-chat |
| Pure reasoning (algorithms) | `claude-ds` opus slot | ds-think |
| Huge context, second opinion | `agy -p ... --mode plan` | gemini-3.8-flash-high |
| QA: test cases, risk analysis | `claude` | Sonnet |
| QA: running tests, exploring a UI, reading logs | `agy` / `codex` | Gemini Flash / Codex |
| QA: bug reports, summaries | `agy` / `claude` | Gemini Flash low / Haiku |
| QA: a bug the cheaper tools could not reproduce | `agy` / `claude` | Opus (Google plan first) |

The Claude and GPT-OSS models on Antigravity share a weekly limit that is separate from your Claude subscription;
check `ai-quota` before relying on them.

Escalate when a cheap run fails twice, or the change touches authorization, money, migrations or API contracts.
The reviewer is never the same vendor as the implementer on risky work.
