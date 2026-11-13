# Behaviour evals

Checks that sdw's prose changes what the model does. Each case runs with and without the plugin.
Optional: it spends model usage, so it is not part of testing or releasing. Run it only on purpose.
Run from the repo root; it needs git ≥2.31 first on PATH and costs about $0.60 per case:

    claude plugin eval . --case commit-via-skill --runs 3 --scaffold --allow-tools Bash --max-cost-usd 3 --no-publish

- `commit-via-skill`: an onboarded repo, "commit this" → no `git commit`, the answer names `/sdw:commit`.
- Results land in `evals/results/` (git-ignored). Never in CI or `tests/run.sh`: it spends your credential.
- Change a case together with the rule it tests. A case that passes both arms tests nothing; rewrite it.
- Last scores: internals §0 "Eval phase 1".
