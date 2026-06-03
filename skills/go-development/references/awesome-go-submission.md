# Submitting a Go Project to awesome-go

How to get a Go library accepted into [avelino/awesome-go](https://github.com/avelino/awesome-go) on the first try. The list is curated and gated by an automated CI suite plus maintainer review; most rejections are mechanical (PR-body format, alphabetical order) rather than quality. This doc captures the exact format the CI parses and the gotchas that aren't in the contributing guide.

## Quick index

| Piece | Where |
|---|---|
| Is the project eligible? | [Eligibility](#eligibility) |
| What the CI validates automatically | [Automated checks](#automated-checks) |
| The single biggest rejection cause | [PR body](#pr-body-1-rejection-cause) |
| README entry format + name collisions | [README entry](#readme-entry) |
| End-to-end submission steps | [Process](#process) |
| Reading the bot's report | [After opening](#after-opening) |

## Eligibility

Verify all of these before starting — most are blocking CI checks:

- **≥ 5 months of repository history** (since first commit). Hard gate; nothing else matters until this passes.
- **Open-source license** — any [OSI-approved](https://opensource.org/licenses/alphabetical) license. *No license = all-rights-reserved = ineligible*, even if the repo is public.
- **`go.mod` at repo root** and **≥ 1 SemVer tag** (`vX.Y.Z`).
- **`pkg.go.dev` page is live** for the module (visit it once / `GOPROXY=https://proxy.golang.org go get <module>@<tag>` to trigger indexing).
- **Go Report Card grade A-, A, or A+** — visit `goreportcard.com/report/<module>` and click **Refresh** so it reflects your latest tag (the score caches on an old version otherwise).
- **A reachable coverage-service link** (Codecov/Coveralls) — a README badge is *not* enough; the bot fetches the URL.
- Category must have **≥ 3 items** (only relevant if creating a new category).

## Automated checks

On PR open, a `github-actions` bot posts a sticky **"Automated Quality Checks"** + **"PR Diff Validation"** report. Know which are blocking:

**Blocking (PR cannot merge):** repo accessible · `go.mod` present · SemVer tag · pkg.go.dev reachable · Go Report Card ≥ A- · **required links present in PR body** · single item per PR · README link matches forge link · description ends with a period · alphabetical order · no duplicate link · entry-format regex · category ≥ 3.

**Warnings only:** OSS license detected · 5-month maturity · CI/CD present · README present · coverage link reachable · link text matches repo name · **non-promotional description** · only `README.md` changed.

> The repo-wide `Running test` job (`TestAlpha`, `TestDuplicatedLinks`) fails on **almost every PR** because `main` itself carries pre-existing alphabetical drift and duplicate links in *unrelated* categories. If your category and project name do **not** appear in that log, the failure is not yours — maintainers merge despite it. Don't try to "fix" it in your PR.

## PR body (#1 rejection cause)

The most common rejection is a PR body the CI can't parse. It does **not** read prose; it extracts the four required links from the template's labeled lines. Fill the current template and put the **visible URL** on each line (not inside an HTML comment):

```markdown
## Required links

- [x] Forge link (github.com, gitlab.com, etc): https://github.com/<org>/<project>
- [x] pkg.go.dev: https://pkg.go.dev/github.com/<org>/<project>
- [x] goreportcard.com: https://goreportcard.com/report/github.com/<org>/<project>
- [x] Coverage service link (codecov, coveralls, etc.): https://app.codecov.io/gh/<org>/<project>

## Pre-submission checklist

- [x] I have read the Contribution Guidelines
- [x] I have read the Quality Standards

## Repository requirements

- [x] `go.mod` file and SemVer release (vX.Y.Z)
- [x] Open source license (<LICENSE>)
- [x] pkg.go.dev link in docs
- [x] goreportcard link (grade A- or better)
- [x] Coverage service link
- [x] Continuous integration (GitHub Actions)

## Pull Request content

- [x] Adds only one package.
- [x] Added in alphabetical order.
- [x] Link text is the exact project name.
- [x] Description is clear, concise, non-promotional, and ends with a period.
- [x] The link in README.md matches the forge link above.
```

Keep it concise — do not add a marketing "About" section; the non-promotional check scans the whole body. Fetch the live template first (`gh api repos/avelino/awesome-go/contents/.github/PULL_REQUEST_TEMPLATE.md --jq .content | base64 -d`) in case it changed.

## README entry

One bullet, in the target category, **alphabetical by visible link text** (case-insensitive), link text = **exact project name**, description **non-promotional and ending with a period**:

```markdown
- [<project>](https://github.com/<org>/<project>) - Concise factual description ending with a period.
```

The non-promotional linter rejects superlatives ("blazing fast", "powerful", "production-grade", "world-class"). State capabilities, not adjectives.

**Same-name collisions:** a different repo with the same project name may already be listed (e.g. two `go-cron`s). This is allowed — the duplicate check is URL-based, and the list already carries cases like two `scheduler` entries. Handle it by:
- Placing your entry **alphabetically adjacent** to the existing one.
- Optionally using **`org/project`** as link text to disambiguate — precedented in-list (e.g. `tickstem/cron`) and a likely reviewer request. This still passes the blocking entry-format regex; it only trips the *non-blocking* "link text matches repo name" warning, so it won't fail CI.
- **Not** bundling a removal of a stale/abandoned same-name entry into your add PR — the one-item-per-PR rule forbids it; file removals separately (and consider whether it's worth the friction).

## Process

```bash
# 1. Fork (no clone) + shallow-clone your fork — the repo history is large
gh repo fork avelino/awesome-go --clone=false
git clone --depth 1 --single-branch https://github.com/<you>/awesome-go.git
cd awesome-go && git checkout -b add-<project>

# 2. Edit README.md: add the single bullet in the right category, alphabetically.
#    Touch ONLY that one line — any unrelated diff hunk gets the PR rejected.

# 3. Verify the diff is exactly one insertion
git diff --stat   # expect: README.md | 1 +

# 4. Clean commit (no attribution/co-author trailers), push
git commit -am "Add <project> to <Category>"
git push -u origin add-<project>

# 5. Open the PR with the body above
gh pr create --repo avelino/awesome-go --base main \
  --head <you>:add-<project> \
  --title "Add <project> to <Category>" --body-file pr-body.md
```

## After opening

- Wait for the bot's sticky report; fix any **blocking** red check and push to the same branch.
- "Detect PR type" should pass as a *package* PR; "Skip quality checks (non-package PR)" showing `skipping` is normal.
- Ignore the legacy `Running test` failure unless your project/category appears in its log (see [above](#automated-checks)).
- awesome-go has a large backlog; merges can take weeks. Don't open duplicate PRs or ping aggressively.
