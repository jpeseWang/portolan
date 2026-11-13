# refs — snapshots of outside systems

Every file here starts with a `fetched` marker naming its source and ttl:

    <!-- fetched: 2026-10-16T09:30 | source: figma <fileKey> v<version> | ttl: 14d -->

Expired means "re-fetch before relying on it", not "delete". Binary exports (PNG frames)
sit next to a `.md` that carries their marker. Never store tokens or credentials here.
