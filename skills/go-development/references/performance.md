<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- SPDX-FileCopyrightText: Netresearch DTT GmbH -->

# Performance: Measure, Then Change

Most Go services are I/O-bound. Their CPU time goes to syscalls, process
starts, logging and the garbage collector, so compiler tricks change little.
This reference gives the order of work: measure the real workload, find what
the measurement shows, change one thing, and measure again.

## 1. Measure the Real Workload

- **Benchmarks:** `for b.Loop()` (see `modernization.md`), always with
  `-benchmem`, at least 6 runs, compared with `benchstat`:

  ```bash
  go test -run '^$' -bench 'BenchmarkX$' -benchmem -count=6 ./pkg/ > old.txt
  # change the code
  go test -run '^$' -bench 'BenchmarkX$' -benchmem -count=6 ./pkg/ > new.txt
  benchstat old.txt new.txt
  ```

- **Profiles of the running service:** import `net/http/pprof` behind a
  flag and bind it to loopback. Profile under a realistic load, not idle:

  ```bash
  curl -o cpu.prof 'http://127.0.0.1:6060/debug/pprof/profile?seconds=60'
  curl -o heap.prof http://127.0.0.1:6060/debug/pprof/heap
  go tool pprof -top -cum ./binary cpu.prof
  go tool pprof -sample_index=alloc_space -top ./binary heap.prof
  ```

- **A profile proposes, the clock decides.** A function with a large share
  of samples or bytes is a candidate. It is a saving only when a paired
  benchmark or load test shows a lower time or a lower resource use.
  Report both numbers, also when the time does not move (a change can cut
  allocations and leave the run time the same).

## 2. Both Arms Must Do the Same Work

Before you compare two configurations, check that each arm did the same
amount of work: count requests, job runs or rows in each arm. An arm that
skips, rejects or queues work uses less CPU and looks faster.

Example: a scheduler with a global limit of 10 concurrent jobs, 30 jobs
firing at the same second. With one thread, each job held its slot longer,
so more runs were skipped: 415 runs against 587 in 40 s. Its lower CPU time
came from less work. With the limit raised to 50, both arms ran 1812 jobs in
60 s, and the CPU difference shrank to 3%.

## 3. GOMAXPROCS in Containers

GOMAXPROCS is the number of threads that run Go code at the same time.

- With a `go 1.25` or later line in `go.mod`, the runtime sets GOMAXPROCS
  from the cgroup CPU limit, rounds a fractional limit up and **never goes
  below 2** unless the machine or the CPU affinity mask has fewer than 2 CPUs
  (`go doc runtime.GOMAXPROCS`). On a host with 2 or more CPUs, a container
  with `--cpus=1` runs Go code on 2 threads.
- With `go 1.24` or older, `GODEBUG=containermaxprocs=0` is the default:
  GOMAXPROCS is `runtime.NumCPU()`, whatever the limit.
- Setting the `GOMAXPROCS` environment variable fixes the value and turns
  off the runtime's automatic update when the limit changes.

2 threads under a 1-CPU quota can use up the quota early in each 100 ms
period, and the process then waits until the next period. That raises the
tail latency of a CPU-busy service. Check before you change anything:

```bash
docker exec <container> cat /sys/fs/cgroup/cpu.stat   # nr_periods, nr_throttled
```

These are the cgroup v2 paths, where the limit is in `cpu.max`. Under
cgroup v1 the counters are in `/sys/fs/cgroup/cpu,cpuacct/cpu.stat` and the
limit in `cpu.cfs_quota_us` and `cpu.cfs_period_us`.

- `nr_throttled` grows with `nr_periods`: test `GOMAXPROCS=1` against the
  default, both arms under the same load (section 2), and compare latency.
- `nr_throttled` stays at 0: GOMAXPROCS is not the problem. Leave the
  default.

Measured on a scheduler (ofelia) with `--cpus=1`, 30 local jobs per second:
throttled in 0 periods in all 6 runs of 60 s, about 1.8% of one CPU. An
I/O-bound service rarely reaches its quota.

Log `runtime.GOMAXPROCS(0)`, `runtime.NumCPU()` and the cgroup limit at
startup, so the chosen value is visible without a debugger
([netresearch/ofelia#972](https://github.com/netresearch/ofelia/pull/972)
is an example).

## 4. Inlining, Escape Analysis and PGO

- `-gcflags` passes flags to the **compiler** (`go help build`), not to the
  garbage collector. `-gcflags=-m` prints inlining and escape decisions.
  Scope it to one package, `-gcflags='example.com/mod/pkg=-m'`; a bare
  `-gcflags=-m` applies only to the packages named on the command line.
- Read `-m` output only for functions the CPU profile shows as hot. A count
  of "cannot inline" lines across a repository is no finding.
- **Profile-guided optimization (PGO)** is the tool that changes inlining
  with data. A CPU profile saved as `default.pgo` in the main package's
  directory is used by every build, because `-pgo=auto` is the default.
  PGO helps only where Go code itself holds the CPU time. Check the flat
  share of your own packages first:

  ```bash
  go tool pprof -top -nodecount=200 ./binary cpu.prof   # flat column, own packages
  ```

  For ofelia, 0 of 240 ms of samples fell into its own code or its cron
  library, and a build with that profile made 0 different inlining decisions
  in its core package (2015 inlined calls with and without PGO).
- Do not hand-inline functions for speed. The compiler inlines small
  functions without help: the ofelia build above inlined 2015 call sites.

## 5. Allocation Traps in the Standard Library

- **`os/exec` output into a non-file writer:** when `Cmd.Stdout` or
  `Cmd.Stderr` is not an `*os.File`, `os/exec` copies the pipe with
  `io.Copy`. `io.Copy` allocates a new 32 KiB buffer for each stream of
  each process, unless the writer implements `io.ReaderFrom`. Wrap the
  writer with a `ReadFrom` that copies with a buffer from a `sync.Pool`.
  Measured: 101 KB to 38 KB allocated per local job run, run time unchanged
  ([netresearch/ofelia#973](https://github.com/netresearch/ofelia/pull/973)).

  ```go
  var copyBuffers = sync.Pool{New: func() any { b := make([]byte, 32*1024); return &b }}

  type pooledCopyWriter struct{ w io.Writer }

  func (p pooledCopyWriter) Write(b []byte) (int, error) { return p.w.Write(b) }

  func (p pooledCopyWriter) ReadFrom(src io.Reader) (int64, error) {
      bufp := copyBuffers.Get().(*[]byte)
      defer copyBuffers.Put(bufp)
      // struct{ io.Writer } hides the writer's own ReadFrom, so CopyBuffer
      // uses the buffer and cannot recurse.
      return io.CopyBuffer(struct{ io.Writer }{p.w}, src, *bufp)
  }
  ```

- **`sync.Pool` pays off for large buffers.** For a small object the pool
  costs more time than it saves: `Get`/`Put` of a `*int` took 6.9 ns, a
  `new(int)` 5.1 ns (Go 1.27, amd64), so pooling saved 8 bytes and lost time.
- **`regexp.MustCompile` inside a function** compiles on every call. Move it
  to a package-level variable when the function runs per request or per job.

## Checklist

1. Profile under the real load, not idle.
2. Name the candidate and its share, then benchmark it paired, at least 6
   runs.
3. Check that both arms did the same work.
4. Report bytes and time, including a time that did not move.
5. In a container, read `cpu.stat` before you touch GOMAXPROCS.
