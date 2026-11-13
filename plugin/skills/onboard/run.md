# run.md — how to run, log in and test (untracked)
Only `## <section>[: <name>]` headings and `- <key>: <value>` lines are data. Never put a password here.
One app per `## app:`; several login recipes as `## login: <app name>`. The second user of role `r` is addressed as role `r-2`; Keychain service `sdw:<PROJ_SLUG>:<role>`, account = user name.

## app: web
- path: <repo>:<prefix>
- start: <command>
- port: <n>
- ready: <url or log text>
- seed: <command> | none
- test-db: testcontainers | in-memory | sqlite | database-url | none
- openapi: <url> | none

## login
- kind: form | api | header | oauth-manual
- url: <login page url, or a path completed from the app's port>
- user-field: <selector>
- pass-field: <selector>
- submit: <selector>
- success: <selector> | url:<glob>
- api: <METHOD> <url>
- api-body: <json with {user} {pass}>
- token-path: <dot path to the token in the api response, for token auth> | none
- token-header: <Name>: <value with {token}> (default `Authorization: Bearer {token}`)
- header: <Name>: <value with {user} and/or {pass}> (kind header: no login request)

## users
- <role>: <user name>, <second user name>

## qa
- QA_WRITE_ENV: local | shared-ask
- artboards: <WxH>, <WxH>
- spec: <projdir-relative spec or design-notes path>, <…> | none
- sandbox: <external side effects safe to trigger: test-mode keys, catch-all mailbox, owned recipients> | none
