# Resilience Patterns in Go

For scheduled jobs, retry-with-backoff, circuit breaker, and timeout
wrappers are built into go-cron — don't hand-roll them. See
`references/cron-scheduling.md` § Resilience Wrappers (`RetryWithBackoff`,
`RetryOnError`, `CircuitBreaker`) and § Concurrency Wrappers (`Timeout`,
`TimeoutWithContext`).

Outside the job scheduler (HTTP clients, background workers), exponential
backoff, circuit breakers, graceful shutdown, rate limiting, and health
checks are standard patterns backed by well-known libraries
(`golang.org/x/time/rate` for rate limiting; `context` + `sync.WaitGroup` +
`os/signal` for graceful shutdown) — no Netresearch-specific convention
beyond what's documented in `references/cron-scheduling.md`.
