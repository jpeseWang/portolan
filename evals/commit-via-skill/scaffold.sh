#!/usr/bin/env bash
# Onboarded single-app repo on a feature branch with one uncommitted edit.
set -eu
git init -q .
git config user.name Eval
git config user.email eval@example.invalid
git symbolic-ref HEAD refs/heads/main
printf 'export function greet(name) {\n  return "Hi " + name;\n}\n' > greet.js
git add greet.js
git commit -qm "init"
git checkout -qb add-greeting
printf 'export function greet(name) {\n  return "Hello, " + name + "!";\n}\n' > greet.js
mkdir -p .sdw .git/info
printf '.sdw/\n' >> .git/info/exclude
printf 'BASE_BRANCH=main\nVCS_HOST=none\n' > .sdw/config.env
printf '## Apps\napp:. (no server)\n## Base branch\nmain\n' > .sdw/project.md
