/**
 * An in-memory stand-in for the slice of Firebase the dispatch path touches:
 * Realtime Database, Firestore (documents, subcollections, equality queries,
 * batches, transactions), Cloud Tasks queues, and a clock.
 *
 * The unit tests beside this mock each call in isolation. This exists so a
 * scenario — several students, a roster of teachers, waves firing on a timer —
 * can run through the real createQuestion, evaluateWave, acceptInvite and
 * rankTeachers and be judged by what ends up stored, the way the apps see it.
 *
 * Not a general-purpose emulator: anything the functions do not use is absent.
 */

// ─── Clock ───────────────────────────────────────────────────────────────────

export const clock = {
  nowMs: 0,
};

// ─── Firestore values ────────────────────────────────────────────────────────

export class FakeTimestamp {
  constructor(private readonly millis: number) {}

  static now(): FakeTimestamp {
    return new FakeTimestamp(clock.nowMs);
  }

  static fromMillis(millis: number): FakeTimestamp {
    return new FakeTimestamp(millis);
  }

  toMillis(): number {
    return this.millis;
  }
}

class ServerTimestampSentinel {}

class ArrayUnionSentinel {
  constructor(readonly values: unknown[]) {}
}

export const FakeFieldValue = {
  serverTimestamp: () => new ServerTimestampSentinel(),
  arrayUnion: (...values: unknown[]) => new ArrayUnionSentinel(values),
};

/** Copies plain objects and arrays, leaving class instances (timestamps) shared. */
function clone<T>(value: T): T {
  if (Array.isArray(value)) return value.map(clone) as unknown as T;
  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) out[k] = clone(v);
    return out as T;
  }
  return value;
}

function resolveWrite(
  existing: Record<string, unknown>,
  patch: Record<string, unknown>
): Record<string, unknown> {
  const next = clone(existing);
  for (const [key, value] of Object.entries(patch)) {
    if (value instanceof ServerTimestampSentinel) {
      next[key] = FakeTimestamp.now();
    } else if (value instanceof ArrayUnionSentinel) {
      const current = Array.isArray(next[key]) ? (next[key] as unknown[]) : [];
      next[key] = [...current, ...value.values.filter((v) => !current.includes(v))];
    } else {
      next[key] = clone(value);
    }
  }
  return next;
}

// ─── Firestore ───────────────────────────────────────────────────────────────

type DocData = Record<string, unknown>;

class FakeDocSnapshot {
  constructor(readonly id: string, private readonly stored: DocData | undefined) {}

  get exists(): boolean {
    return this.stored !== undefined;
  }

  data(): DocData | undefined {
    return this.stored === undefined ? undefined : clone(this.stored);
  }
}

class FakeQuerySnapshot {
  constructor(readonly docs: FakeDocSnapshot[]) {}

  get size(): number {
    return this.docs.length;
  }

  get empty(): boolean {
    return this.docs.length === 0;
  }
}

export class FakeDocRef {
  constructor(private readonly store: FakeFirestore, readonly path: string) {}

  get id(): string {
    return this.path.split("/").pop() as string;
  }

  collection(name: string): FakeQuery {
    return new FakeQuery(this.store, `${this.path}/${name}`);
  }

  async get(): Promise<FakeDocSnapshot> {
    return this.store.snapshot(this.path);
  }

  async set(data: DocData): Promise<void> {
    this.store.write(this.path, data, false);
  }

  async update(data: DocData): Promise<void> {
    this.store.write(this.path, data, true);
  }
}

export class FakeQuery {
  constructor(
    private readonly store: FakeFirestore,
    readonly collectionPath: string,
    private readonly filters: Array<[string, unknown]> = [],
    private readonly max = Infinity
  ) {}

  doc(id: string): FakeDocRef {
    return new FakeDocRef(this.store, `${this.collectionPath}/${id}`);
  }

  where(field: string, op: string, value: unknown): FakeQuery {
    if (op !== "==") throw new Error(`fake Firestore supports only ==, got ${op}`);
    return new FakeQuery(this.store, this.collectionPath, [...this.filters, [field, value]], this.max);
  }

  limit(n: number): FakeQuery {
    return new FakeQuery(this.store, this.collectionPath, this.filters, n);
  }

  async get(): Promise<FakeQuerySnapshot> {
    return this.run();
  }

  run(): FakeQuerySnapshot {
    const docs = this.store
      .childrenOf(this.collectionPath)
      .filter(([, data]) => this.filters.every(([field, value]) => data[field] === value))
      .slice(0, this.max)
      .map(([path, data]) => new FakeDocSnapshot(path.split("/").pop() as string, data));
    return new FakeQuerySnapshot(docs);
  }
}

class FakeTransaction {
  readonly writes: Array<() => void> = [];

  constructor(private readonly store: FakeFirestore) {}

  async get(target: FakeDocRef | FakeQuery): Promise<FakeDocSnapshot | FakeQuerySnapshot> {
    if (target instanceof FakeDocRef) return this.store.snapshot(target.path);
    return target.run();
  }

  set(ref: FakeDocRef, data: DocData): void {
    this.writes.push(() => this.store.write(ref.path, data, false));
  }

  update(ref: FakeDocRef, data: DocData): void {
    this.writes.push(() => this.store.write(ref.path, data, true));
  }
}

export class FakeFirestore {
  private readonly docs = new Map<string, DocData>();
  /** Transactions run one at a time, which is the guarantee real ones give. */
  private txChain: Promise<unknown> = Promise.resolve();

  reset(): void {
    this.docs.clear();
    this.txChain = Promise.resolve();
  }

  collection(name: string): FakeQuery {
    return new FakeQuery(this, name);
  }

  batch() {
    const writes: Array<() => void> = [];
    return {
      set: (ref: FakeDocRef, data: DocData) => {
        writes.push(() => this.write(ref.path, data, false));
      },
      update: (ref: FakeDocRef, data: DocData) => {
        writes.push(() => this.write(ref.path, data, true));
      },
      commit: async () => {
        writes.forEach((w) => w());
      },
    };
  }

  runTransaction<T>(work: (tx: FakeTransaction) => Promise<T>): Promise<T> {
    const run = this.txChain.then(async () => {
      const tx = new FakeTransaction(this);
      const result = await work(tx);
      tx.writes.forEach((w) => w());
      return result;
    });
    this.txChain = run.catch(() => undefined);
    return run;
  }

  // ── storage ──

  snapshot(path: string): FakeDocSnapshot {
    return new FakeDocSnapshot(path.split("/").pop() as string, this.docs.get(path));
  }

  write(path: string, data: DocData, merge: boolean): void {
    const existing = this.docs.get(path);
    if (merge && existing === undefined) {
      throw new Error(`fake Firestore: update on missing document ${path}`);
    }
    this.docs.set(path, resolveWrite(merge ? existing ?? {} : {}, data));
  }

  childrenOf(collectionPath: string): Array<[string, DocData]> {
    const depth = collectionPath.split("/").length + 1;
    return [...this.docs.entries()].filter(
      ([path]) => path.startsWith(`${collectionPath}/`) && path.split("/").length === depth
    );
  }

  /** Test-side read of one document, or undefined. */
  read(path: string): DocData | undefined {
    const data = this.docs.get(path);
    return data === undefined ? undefined : clone(data);
  }

  /** Test-side read of a collection, keyed by document id. */
  readCollection(collectionPath: string): Record<string, DocData> {
    const out: Record<string, DocData> = {};
    for (const [path, data] of this.childrenOf(collectionPath)) {
      out[path.split("/").pop() as string] = clone(data);
    }
    return out;
  }
}

// ─── Realtime Database ───────────────────────────────────────────────────────

function segments(path: string): string[] {
  return path.split("/").filter(Boolean);
}

class FakeRtdbSnapshot {
  constructor(private readonly value: unknown) {}

  val(): unknown {
    return this.value === undefined ? null : clone(this.value);
  }

  exists(): boolean {
    return this.value !== undefined && this.value !== null;
  }

  child(path: string): FakeRtdbSnapshot {
    let node: unknown = this.value;
    for (const key of segments(path)) {
      node = node && typeof node === "object" ? (node as Record<string, unknown>)[key] : undefined;
    }
    return new FakeRtdbSnapshot(node);
  }
}

export class FakeRtdbRef {
  constructor(private readonly db: FakeRealtimeDatabase, private readonly path: string) {}

  child(path: string): FakeRtdbRef {
    return new FakeRtdbRef(this.db, `${this.path}/${path}`);
  }

  async once(_event: "value"): Promise<FakeRtdbSnapshot> {
    return new FakeRtdbSnapshot(this.db.read(this.path));
  }

  async get(): Promise<FakeRtdbSnapshot> {
    return this.once("value");
  }

  async set(value: unknown): Promise<void> {
    this.db.write(this.path, value);
  }

  async update(patch: Record<string, unknown>): Promise<void> {
    for (const [key, value] of Object.entries(patch)) {
      this.db.write(`${this.path}/${key}`, value);
    }
  }

  async remove(): Promise<void> {
    this.db.write(this.path, null);
  }

  orderByChild(field: string) {
    return {
      equalTo: (expected: unknown) => ({
        once: async (_event: "value") => {
          const node = this.db.read(this.path);
          const matches: Record<string, unknown> = {};
          if (node && typeof node === "object") {
            for (const [key, child] of Object.entries(node as Record<string, unknown>)) {
              if ((child as Record<string, unknown>)?.[field] === expected) matches[key] = child;
            }
          }
          return new FakeRtdbSnapshot(Object.keys(matches).length > 0 ? matches : null);
        },
      }),
    };
  }
}

export class FakeRealtimeDatabase {
  private root: Record<string, unknown> = {};

  reset(): void {
    this.root = {};
  }

  ref(path = ""): FakeRtdbRef {
    return new FakeRtdbRef(this, path);
  }

  read(path: string): unknown {
    let node: unknown = this.root;
    for (const key of segments(path)) {
      if (!node || typeof node !== "object") return undefined;
      node = (node as Record<string, unknown>)[key];
    }
    return node === undefined ? undefined : clone(node);
  }

  write(path: string, value: unknown): void {
    const keys = segments(path);
    const last = keys.pop() as string;
    let node = this.root;
    for (const key of keys) {
      if (!node[key] || typeof node[key] !== "object") {
        if (value === null) return;
        node[key] = {};
      }
      node = node[key] as Record<string, unknown>;
    }
    if (value === null || value === undefined) {
      delete node[last];
    } else {
      node[last] = clone(value);
    }
  }
}

// ─── Cloud Tasks ─────────────────────────────────────────────────────────────

export interface ScheduledTask {
  queue: string;
  payload: Record<string, unknown>;
  runAtMs: number;
  delaySeconds: number;
}

export class FakeTaskQueues {
  pending: ScheduledTask[] = [];
  /** Every task ever enqueued, including the ones already run. */
  history: ScheduledTask[] = [];

  reset(): void {
    this.pending = [];
    this.history = [];
  }

  taskQueue(queue: string) {
    return {
      enqueue: async (
        payload: Record<string, unknown>,
        options: { scheduleDelaySeconds?: number } = {}
      ) => {
        const delaySeconds = options.scheduleDelaySeconds ?? 0;
        const task = { queue, payload, delaySeconds, runAtMs: clock.nowMs + delaySeconds * 1000 };
        this.pending.push(task);
        this.history.push(task);
      },
    };
  }

  /** Removes and returns the earliest task due at or before `atMs`, if any. */
  takeNextDue(atMs: number): ScheduledTask | undefined {
    const due = this.pending
      .filter((t) => t.runAtMs <= atMs)
      .sort((a, b) => a.runAtMs - b.runAtMs)[0];
    if (due) this.pending.splice(this.pending.indexOf(due), 1);
    return due;
  }
}

// ─── Singletons shared by the module mocks and the test ──────────────────────

export const fakeFirestore = new FakeFirestore();
export const fakeRtdb = new FakeRealtimeDatabase();
export const fakeTasks = new FakeTaskQueues();

export function resetFakeFirebase(startMs: number): void {
  clock.nowMs = startMs;
  fakeFirestore.reset();
  fakeRtdb.reset();
  fakeTasks.reset();
}
