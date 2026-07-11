# Go Architecture Patterns

## Package Structure

Standard Go convention: `cmd/` for entry points, `internal/` for private
packages, one directory per bounded concern (business logic, CLI, HTTP
layer, config). See
[golang-standards/project-layout](https://github.com/golang-standards/project-layout)
for a common (if unofficial) community reference — there is no
Netresearch-specific override.

## State Mutation Completeness

When an operation changes an object's state, update **all** tracking fields in
the same place — not just the one you came to change. Partial updates leave the
object internally inconsistent and produce bugs that are hard to trace back to
their cause.

```go
// After a run, update every field that describes "what happened",
// on both the success and failure paths:
func (j *Job) recordRun(start time.Time, err error) {
    j.LastRunTime = start
    j.LastDuration = time.Since(start)
    j.RunCount++
    j.LastError = err
    if err != nil {
        j.FailureCount++
        j.Status = StatusFailed
    } else {
        j.Status = StatusCompleted
    }
}
```

Anti-pattern: bumping `RunCount` but forgetting `LastError`/`Status`, so a failed
run still reports as "completed". Keep the mutation in one method so the full set
is always updated together.

## Job-Scheduler Reference Implementation

The concrete job interface hierarchy (`BareJob`, `ExecJob`/`RunJob`/`LocalJob`),
resilient-job wrapper, middleware chain (logging/metrics/notification),
scheduler core loop, and jobs REST API previously documented here describe
ofelia's actual implementation, not a general Go convention.

Follow-up (not done in this PR): move them to the `netresearch/ofelia` repo's
`AGENTS.md`. In the meantime, see `references/cron-scheduling.md` for the
general-purpose `netresearch/go-cron` library API.
