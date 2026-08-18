# Branch Protection Standard for Go Repositories

The default-branch gate for Netresearch Go repos, measured as the estate
watermark (highest standard per axis across the Go, TYPO3, and skill repos)
and applied to all seven Go repos on 2026-08-18. Use it as the minimum for
every new Go repo.

## Use rulesets, never classic branch protection

Classic protection's review settings are **invisible to the
`repos/{r}/rules/branches/{branch}` API** — tooling that reasons from the
rules endpoint (pr-status, preflight scripts) cannot see them, so a gate like
`require_last_push_approval` surfaces only after everything else is green.
Rulesets are the single queryable source of truth.

## Three rulesets, not one

Bypass actors attach to a **whole ruleset**. Splitting isolates the
deliberate bypass (deps automation on the approval rule) from the rules that
must never be bypassed (signatures, checks):

| Ruleset | Rules | Bypass |
|---|---|---|
| `go-baseline` | `deletion`, `non_fast_forward`, `required_status_checks` (strict; the ten `go-check / *` contexts + `drift / Template drift`), `code_scanning` (CodeQL, high_or_higher/errors) | none |
| `require-signed-commits` | `required_signatures` | none |
| `go-pull-request` | `pull_request`: 1 approval, dismiss stale on push, thread resolution required, merge-commit only, **no** last-push approval, **no** code-owner review | Repo admins, Renovate (app 2740), Dependabot (app 29110) — all `bypass_mode: pull_request` |

A separate `Copilot review for default branch` ruleset
(`copilot_code_review`, `review_on_push: false`) usually already exists; keep
it, do not duplicate the rule.

Repos without the shared `go-check` template scale `go-baseline`'s check
contexts to the jobs that actually run — a required context that no workflow
emits blocks every merge forever.

## Rules with a rationale

- **`require_last_push_approval` stays off.** With a bot-maintainer flow
  (agent pushes review follow-ups, then reviews), the bot is the last pusher
  and its approval is discounted — structurally unresolvable without a second
  human (deadlocked go-cron#399). Approver ≠ author, stale-review dismissal,
  and thread resolution give the protection without the deadlock.
- **CI must be in `required_status_checks`.** go-cron required only the
  template-drift check for months: a red test suite did not block merge.
- **`require_code_owner_reviews` only with a CODEOWNERS that resolves.**
  GitHub ignores unresolvable owners; a CODEOWNERS pointing at a nonexistent
  team makes the flag vacuous while reading as enforcement (go-cron#400).
- **Bypass mode `pull_request`, never `always`.** `always` lets the actor
  push past non-fast-forward and checks; `pull_request` only relaxes the
  approval rule for the actor's own PRs (Renovate/Dependabot auto-merge).
- **Merge-commit only** (`allowed_merge_methods: ["merge"]`) — atomic
  commits, preserved signatures.

## Applying to a repo

```bash
# Payload shape: {name, target: "branch", enforcement: "active",
#   conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
#   bypass_actors: [...], rules: [...]}
gh api repos/OWNER/REPO/rulesets -X POST --input go-baseline.json
gh api repos/OWNER/REPO/rulesets -X POST --input require-signed-commits.json
gh api repos/OWNER/REPO/rulesets -X POST --input go-pull-request.json
# Read the EFFECTIVE rules back — a 2xx is not proof:
gh api repos/OWNER/REPO/rules/branches/main --jq '[.[].type] | sort'
# Then retire classic protection:
gh api repos/OWNER/REPO/branches/main/protection -X DELETE
```

Copy a live ruleset as the template instead of hand-writing JSON:
`gh api repos/netresearch/go-cron/rulesets --jq '.[]|{id,name}'`, then `GET`
the id and adjust. Org-level rulesets would replace the per-repo copies, but
require a paid GitHub plan (the free org tier returns 403).

## CODEOWNERS and reviewer routing

The standard file (copied verbatim across the Go repos):

```text
* @CybotTM @netresearch/netresearch

/.github/workflows/ @CybotTM @netresearch/sec
/SECURITY.md @CybotTM @netresearch/sec
```

No per-repo maintainer teams exist — use the org-wide teams. Two vacuity
traps, both observed live: a CODEOWNERS entry naming a **nonexistent team** is
silently ignored, and so is one naming a team **without read access to the
repo** (the `netresearch` team had access to none of the seven Go repos, so
the default-owner line never routed anywhere). After editing CODEOWNERS,
verify access: `gh api orgs/ORG/teams/TEAM/repos/ORG/REPO` — grant with
`-X PUT -f permission=pull`.

The 1-approval rule is satisfied on solo-maintained repos by the org-shared
`pr-quality.yml` caller (`auto-approve-maintainers: true`). A repo without it
has **no approval source**: nothing can merge, and ruleset bypass does not
apply to a plain `gh pr merge` (only to the explicit admin-bypass path, which
is banned). Ship the workflow before or with the ruleset.

## Two rollout traps

- **A required check must always report.** Deriving required contexts from a
  push run on main is not enough: a workflow whose `pull_request` trigger has
  `paths:` filters never starts on non-matching PRs, and the required check
  hangs "expected" forever. Remove path filters from the PR trigger of any
  workflow whose job is a required context.
- **Repo merge methods must include the ruleset's allowed method.** A repo
  with `allow_merge_commit: false` plus a ruleset allowing only `merge` can
  merge nothing at all. Check `gh api repos/OWNER/REPO --jq
  '{allow_merge_commit, allow_rebase_merge, allow_squash_merge}'` when
  applying the ruleset.
