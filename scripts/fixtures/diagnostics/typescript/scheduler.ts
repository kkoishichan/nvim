/**
 * Task scheduler sample with deliberate diagnostics (vtsls, strict tsconfig).
 *
 * Intended findings:
 *   - 6133 unused locals / imports
 *   - 7006 parameter implicitly has an any type
 *   - 2322 type mismatch on assignment
 *   - 2339 property does not exist on type
 *   - 18048 / 2532 value is possibly undefined
 *   - 7030 not all code paths return a value
 *   - 7027 unreachable code detected
 *   - 2554 wrong number of arguments
 *   - 2367 comparison appears unintentional (no overlap)
 *   - 2578 unused @ts-expect-error directive
 *   - 2741 property missing in object literal
 *   - 2588 cannot assign to const
 *   - 7029 fallthrough case in switch
 */

export type Priority = "low" | "normal" | "high" | "critical";

export interface TaskSpec {
  readonly id: string;
  readonly name: string;
  readonly priority: Priority;
  readonly dependsOn: readonly string[];
  readonly estimateMinutes: number;
  readonly deadline?: Date;
}

export interface TaskRun {
  readonly id: string;
  startedAt: Date;
  finishedAt?: Date;
  attempts: number;
  error?: string;
}

export type TaskState = "pending" | "ready" | "running" | "done" | "failed";

const PRIORITY_WEIGHT: Record<Priority, number> = {
  low: 1,
  normal: 2,
  high: 4,
  critical: 8,
};

const unusedConstant = 42; // diag: declared but never read (6133)

class SchedulerError extends Error {
  constructor(message: string, readonly taskId?: string) {
    super(message);
    this.name = "SchedulerError";
  }
}

function assertNever(value: never): never {
  throw new SchedulerError(`unexpected value ${String(value)}`);
}

export class Clock {
  private offsetMs = 0;

  now(): Date {
    return new Date(Date.now() + this.offsetMs);
  }

  advance(minutes: number): void {
    this.offsetMs += minutes * 60_000;
  }
}

export class TaskGraph {
  private readonly specs = new Map<string, TaskSpec>();
  private readonly dependents = new Map<string, Set<string>>();

  add(spec: TaskSpec): void {
    if (this.specs.has(spec.id)) {
      throw new SchedulerError(`duplicate task ${spec.id}`, spec.id);
    }
    this.specs.set(spec.id, spec);
    for (const dependency of spec.dependsOn) {
      let set = this.dependents.get(dependency);
      if (!set) {
        set = new Set();
        this.dependents.set(dependency, set);
      }
      set.add(spec.id);
    }
  }

  get(id: string): TaskSpec | undefined {
    return this.specs.get(id);
  }

  all(): TaskSpec[] {
    return [...this.specs.values()];
  }

  dependentsOf(id: string): string[] {
    return [...(this.dependents.get(id) ?? [])];
  }

  validate(): string[] {
    const problems: string[] = [];
    for (const spec of this.specs.values()) {
      for (const dependency of spec.dependsOn) {
        if (!this.specs.has(dependency)) {
          problems.push(`${spec.id} depends on unknown task ${dependency}`);
        }
      }
    }
    const visiting = new Set<string>();
    const visited = new Set<string>();
    const visit = (id: string, trail: string[]): void => {
      if (visited.has(id)) {
        return;
      }
      if (visiting.has(id)) {
        problems.push(`cycle: ${[...trail, id].join(" -> ")}`);
        return;
      }
      visiting.add(id);
      for (const dependency of this.specs.get(id)?.dependsOn ?? []) {
        visit(dependency, [...trail, id]);
      }
      visiting.delete(id);
      visited.add(id);
    };
    for (const id of this.specs.keys()) {
      visit(id, []);
    }
    return problems;
  }

  topologicalOrder(): string[] {
    const indegree = new Map<string, number>();
    for (const spec of this.specs.values()) {
      indegree.set(spec.id, spec.dependsOn.length);
    }
    const queue = [...indegree.entries()].filter(([, degree]) => degree === 0).map(([id]) => id);
    const order: string[] = [];
    while (queue.length > 0) {
      const id = queue.shift()!;
      order.push(id);
      for (const dependent of this.dependentsOf(id)) {
        const remaining = indegree.get(dependent)! - 1;
        indegree.set(dependent, remaining);
        if (remaining === 0) {
          queue.push(dependent);
        }
      }
    }
    return order;
  }
}

export class Scheduler {
  private readonly state = new Map<string, TaskState>();
  private readonly runs = new Map<string, TaskRun>();
  private readonly log: string[] = [];

  constructor(
    private readonly graph: TaskGraph,
    private readonly clock: Clock,
    private readonly maxAttempts = 3,
  ) {
    for (const spec of graph.all()) {
      this.state.set(spec.id, spec.dependsOn.length === 0 ? "ready" : "pending");
    }
  }

  stateOf(id: string): TaskState {
    const state = this.state.get(id);
    if (state === undefined) {
      throw new SchedulerError(`unknown task ${id}`, id);
    }
    return state;
  }

  ready(): TaskSpec[] {
    return this.graph
      .all()
      .filter((spec) => this.state.get(spec.id) === "ready")
      .sort((left, right) => this.score(right) - this.score(left));
  }

  private score(spec: TaskSpec): number {
    const weight = PRIORITY_WEIGHT[spec.priority];
    const deadlineBonus = spec.deadline ? Math.max(0, 1_000 - this.minutesUntil(spec.deadline)) : 0;
    return weight * 100 + deadlineBonus + this.graph.dependentsOf(spec.id).length;
  }

  private minutesUntil(deadline: Date): number {
    return Math.round((deadline.getTime() - this.clock.now().getTime()) / 60_000);
  }

  start(id: string): TaskRun {
    if (this.stateOf(id) !== "ready") {
      throw new SchedulerError(`task ${id} is not ready`, id);
    }
    const previous = this.runs.get(id);
    const run: TaskRun = {
      id,
      startedAt: this.clock.now(),
      attempts: (previous?.attempts ?? 0) + 1,
    };
    this.runs.set(id, run);
    this.state.set(id, "running");
    this.log.push(`${run.startedAt.toISOString()} start ${id} attempt ${run.attempts}`);
    return run;
  }

  finish(id: string, error?: string): void {
    const run = this.runs.get(id);
    run.finishedAt = this.clock.now(); // diag: run is possibly undefined (18048)
    if (error) {
      run.error = error;
      this.state.set(id, run.attempts >= this.maxAttempts ? "failed" : "ready");
      return;
    }
    this.state.set(id, "done");
    for (const dependent of this.graph.dependentsOf(id)) {
      const spec = this.graph.get(dependent)!;
      if (spec.dependsOn.every((dependency) => this.state.get(dependency) === "done")) {
        this.state.set(dependent, "ready");
      }
    }
  }

  describe(id: string): string {
    const state = this.stateOf(id);
    switch (state) {
      case "pending":
        return "waiting for dependencies";
      case "ready":
        return "ready to start";
      case "running": // diag: fallthrough into the next case (7029)
        this.log.push(`describe ${id}`);
      case "done":
        return "completed";
      case "failed":
        return "gave up";
      default:
        return assertNever(state);
    }
  }

  retryBudget(id: string): number {
    const run = this.runs.get(id);
    if (run) {
      return this.maxAttempts - run.attempts;
    }
    // diag: not all code paths return a value (7030)
  }

  history(): readonly string[] {
    return this.log;
  }
}

export function totalEstimate(specs: TaskSpec[]): number {
  let total: number = "0"; // diag: string is not assignable to number (2322)
  for (const spec of specs) {
    total += spec.estimateMinutes;
  }
  return total;
}

export function criticalPath(graph: TaskGraph): string[] {
  const order = graph.topologicalOrder();
  const longest = new Map<string, { minutes: number; via?: string }>();
  for (const id of order) {
    const spec = graph.get(id)!;
    let best = { minutes: spec.estimateMinutes, via: undefined as string | undefined };
    for (const dependency of spec.dependsOn) {
      const candidate = longest.get(dependency)!.minutes + spec.estimateMinutes;
      if (candidate > best.minutes) {
        best = { minutes: candidate, via: dependency };
      }
    }
    longest.set(id, best);
  }
  let cursor = [...longest.entries()].sort((a, b) => b[1].minutes - a[1].minutes)[0]?.[0];
  const path: string[] = [];
  while (cursor) {
    path.unshift(cursor);
    cursor = longest.get(cursor)?.via;
  }
  return path;
}

export function formatRun(run: TaskRun): string {
  const duration = run.finishedAt ? run.finishedAt.getTime() - run.startedAt.getTime() : 0;
  return `${run.id}: ${run.attempts} attempt(s), ${duration} ms, ${run.errorMessage ?? "ok"}`; // diag: property does not exist (2339)
}

export function parseSpec(raw) { // diag: parameter implicitly any (7006)
  return {
    id: String(raw.id),
    name: String(raw.name),
    priority: raw.priority,
    dependsOn: raw.dependsOn ?? [],
    estimateMinutes: Number(raw.estimate),
  };
}

export function isUrgent(spec: TaskSpec): boolean {
  if (spec.priority === "urgent") { // diag: no overlap between Priority and "urgent" (2367)
    return true;
  }
  return spec.priority === "critical";
}

export function buildDemo(): { graph: TaskGraph; scheduler: Scheduler; clock: Clock } {
  const graph = new TaskGraph();
  const clock = new Clock();
  const specs: TaskSpec[] = [
    { id: "fetch", name: "Fetch sources", priority: "normal", dependsOn: [], estimateMinutes: 5 },
    { id: "build", name: "Build", priority: "high", dependsOn: ["fetch"], estimateMinutes: 20 },
    { id: "unit", name: "Unit tests", priority: "high", dependsOn: ["build"], estimateMinutes: 15 },
    { id: "lint", name: "Lint", priority: "low", dependsOn: ["fetch"], estimateMinutes: 4 },
    { id: "package", name: "Package", priority: "critical", dependsOn: ["unit", "lint"], estimateMinutes: 8 },
    { id: "publish", priority: "critical", dependsOn: ["package"], estimateMinutes: 3 }, // diag: missing name (2741)
  ];
  for (const spec of specs) {
    graph.add(spec);
  }
  const scheduler = new Scheduler(graph, clock, 3, true); // diag: too many arguments (2554)
  return { graph, scheduler, clock };
}

export function runDemo(): string[] {
  const { graph, scheduler, clock } = buildDemo();
  const problems = graph.validate();
  if (problems.length > 0) {
    return problems;
  }
  const transcript: string[] = [];
  for (let round = 0; round < 10; round += 1) {
    const ready = scheduler.ready();
    if (ready.length === 0) {
      break;
    }
    for (const spec of ready) {
      scheduler.start(spec.id);
      clock.advance(spec.estimateMinutes);
      scheduler.finish(spec.id, spec.id === "lint" && round === 0 ? "flaky lint" : undefined);
      transcript.push(`${spec.id}: ${scheduler.describe(spec.id)}`);
    }
  }
  const estimate = totalEstimate(graph.all());
  estimate = 0; // diag: cannot assign to const (2588)
  transcript.push(`critical path: ${criticalPath(graph).join(" -> ")}`);
  return transcript;
  transcript.push("never reached"); // diag: unreachable code (7027)
}

// @ts-expect-error diag: unused directive because the next line is valid (2578)
export const demoTranscript: string[] = runDemo();
