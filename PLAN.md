# Engineer Assistant — Plan

A native macOS app that teaches a high-school STEM student about MacOS and Linux. The app has two modes:

- **Ask Mode** — open-ended Q&A with Claude about system administration, coding, MacOS, Linux, or anything adjacent. Conversational, multi-turn.
- **Course Mode** — the student names a subject; Claude generates a short course conforming to a fixed schema; the student works through it with hands-on exercises in a real, sandboxed shell.

Every chat message and shell interaction in both modes is logged so a parent or instructor can review what was asked and learned.

---

## Scope & Audience

- **Hardware**: M1 Mac Mini (single device).
- **Users**: one student + one supervising adult (parent / instructor).
- **Topics**: MacOS shell, Linux bash, system administration on both, Claude Code usage, basic website setup/admin, and similar.
- **Out of scope (deliberately)**: multi-user, cloud sync, auth, course marketplace, offline LLM, multi-LLM abstraction, mobile.

---

## Design Decisions (locked)

| Decision | Choice |
|---|---|
| App stack | Native SwiftUI on macOS |
| Interactivity | Real shell, sandboxed |
| LLM provider | Anthropic Claude (single provider, API key in Keychain) |
| Container runtime for Linux | **Podman** default, Docker fallback |
| Student model | Single student |
| Course caching | Aggressive — cache by subject; explicit "Regenerate" button |
| Recording | Full chat + shell I/O + lesson events captured to SQLite |
| Instructor access | PIN gate, with one-time recovery code shown at setup |
| Log retention | Forever — no rotation |
| Session boundary | App launch → quit or 30 min idle |

---

## The Two Modes

The student picks a mode via a toggle at the top of the chat: **Ask** | **Course**. Both modes share the same chat UI and message history, but behave differently under the hood.

### Ask Mode
- Default mode on launch.
- Free-form conversational Q&A. Multi-turn — Claude sees prior turns in the same session.
- System prompt frames Claude as a patient tutor for a high-school STEM student; encourages short, example-driven answers; suggests switching to Course Mode if a question would be better served by a structured walkthrough.
- Topic scope is intentionally broader than just MacOS/Linux — coding questions, sysadmin questions, conceptual questions all welcome.
- Streaming responses (typical chat UX).
- Events tagged with `mode: "ask"`.

### Course Mode
- Student names a subject; Claude generates a single `Course` JSON via tool-use (schema below).
- Single-shot, not multi-turn. Each course is its own artifact.
- Aggressively cached on disk; re-asking the same subject reuses the cached course unless the student presses `Regenerate`.
- Events tagged with `mode: "course"`.
- Once a course is generated, control moves to the **Course Player** view (still inside the same window).

### A third source of chat: lesson-scoped
Inside the Course Player, the `Ask Claude` control opens a sidebar that asks Claude in the *context* of the current lesson. Those messages are logged as `chat_user`/`chat_assistant` events with `course_id` and `lesson_idx` set, and `mode: "ask"` (since they are still free-form). The instructor dashboard can therefore filter to "free-form questions only" (mode=ask, course_id=null) versus "lesson follow-ups" (mode=ask, course_id set).

---

## The Course Schema

This is the most important architectural decision. **Every course Claude generates conforms to this schema.** Same shape ⇒ same UI ⇒ predictable controls.

```
Course
├── title
├── description
├── estimated_minutes
├── environment: "macos" | "linux"
├── prerequisites: [string]
├── lessons[]
│   ├── title
│   ├── concept_md          (markdown explanation, ~150 words)
│   ├── demos[]             (command, expected_output, explanation)
│   ├── practice_prompt     (open exploration in the shell)
│   └── challenge
│       ├── task            (what to accomplish)
│       ├── starter_state   (files / env to set up in the sandbox)
│       └── verify          (deterministic check, see below)
│           type: "exit_code" | "stdout_regex" | "file_exists" | "file_contains" | "llm_judge"
│           value: ...
└── final_challenge          (same shape as challenge)
```

Course generation uses Anthropic tool-use with this schema as the tool input. The client validates the response; malformed responses are rejected and re-requested. Valid courses are cached to disk keyed by subject + environment.

### Verification — deterministic first
- `exit_code` — last command's exit status equals N.
- `stdout_regex` — last command's stdout matches regex.
- `file_exists` — path exists in the sandbox.
- `file_contains` — file contains substring/regex.
- `llm_judge` — fallback for open-ended challenges; uses an extra Claude call with the transcript. Marked explicitly in schema so it's rare.

---

## Standardized Lesson Flow

Every lesson has the same five panels and six controls. This consistency is what makes the app feel like a coherent learning environment instead of "whatever the LLM emitted today."

**Panels (in order):** Concept → Demos → Practice → Challenge → Recap
**Controls:** `Next` `Prev` `Reset Sandbox` `Hint` `Skip` `Ask Claude`

`Ask Claude` opens a lesson-scoped chat sidebar; the student can ask follow-up questions without losing context. Those messages are still logged, tagged with the lesson they came from.

---

## Architecture

```
┌─────────────────────── SwiftUI App ─────────────────────────┐
│  Sidebar         │  Main View                               │
│  - Course list   │  ┌─ Chat [Ask | Course] ─┐  or           │
│  - Progress      │  │   messages...         │  ┌─ Lesson ─┐ │
│                  │  │   input field         │  │ Concept  │ │
│                  │  └───────────────────────┘  │ Demos    │ │
│                  │                             │ Practice │ │
│                  │  ┌─ Embedded Terminal ──┐   │ Challenge│ │
│                  │  │  $ ls                │   │ Recap    │ │
│                  │  └──────────────────────┘   └──────────┘ │
└─────────────────────────────────────────────────────────────┘
       │                    │                    │
   Keychain           Anthropic API         Sandbox Runtime
   (API key,          (chat streaming +     ┌──────┴────────┐
    PIN hash,          tool-use for         MacOS          Linux
    recovery code)     Course JSON)         sandbox-exec   Podman /
                                            zsh PTY        Docker
                            │                              container
                            ▼
                    ┌─ Event Log (SQLite via GRDB) ─┐
                    │  sessions, events             │
                    └───────────────────────────────┘
                            │
                            ▼
                    Instructor Dashboard
                    (PIN-gated view)
```

### Key components

1. **Claude client** — streaming chat for conversational turns; tool-use with the `Course` schema for course generation. Keychain-backed key storage.
2. **Course generator** — single Claude call returning `Course` JSON; validates; caches to `~/Library/Application Support/EngineerAssistant/courses/<id>.json`.
3. **Course player** — pure SwiftUI views bound to the schema; written once, reused for every course.
4. **Sandbox runtime** — protocol with two implementations:
   - `MacOSSandbox`: spawns `zsh` via PTY in `~/Library/Application Support/EngineerAssistant/sandboxes/<course-id>/`, wrapped in a `sandbox-exec` profile that denies network (unless lesson opts in), writes outside the sandbox dir, `sudo`, and key system paths.
   - `LinuxSandbox`: uses Podman (or Docker as fallback) to run an Alpine/Ubuntu container per course; commands proxied via `exec`. Container is ephemeral; `Reset Sandbox` destroys and respawns.
5. **PTY tee** — every byte read/written on the PTY master fd is mirrored into the event log before being forwarded to the terminal view. This is how shell history is captured — there's no separate history file.
6. **Verifier** — deterministic checks first; LLM-as-judge only when schema requests it.
7. **Event log** — append-only SQLite store (see below).
8. **Instructor dashboard** — separate, PIN-gated view in the same app.

---

## Recording: Sessions & Events

A **session** = one app launch, ending on quit or 30 minutes of inactivity. Every chat message is recorded regardless of whether it triggers a course generation.

### Schema (SQLite via GRDB.swift)

```sql
sessions
  id              TEXT PRIMARY KEY
  started_at      INTEGER  -- unix ms
  ended_at        INTEGER  -- nullable until session closes
  end_reason      TEXT     -- "quit" | "idle" | "active"

events            -- append-only, ordered by ts
  id              INTEGER PRIMARY KEY AUTOINCREMENT
  session_id      TEXT REFERENCES sessions(id)
  ts              INTEGER  -- unix ms
  type            TEXT
  course_id       TEXT     -- nullable; set when tied to a course
  lesson_idx      INTEGER  -- nullable; set when tied to a specific lesson
  payload_json    TEXT     -- type-specific payload
```

### Event types

| type | payload |
|---|---|
| `chat_user` | `{ text, mode }` where `mode` is `"ask"` or `"course"` |
| `chat_assistant` | `{ text, mode, model, usage }` |
| `shell_stdin` | `{ bytes_b64 }` (keystrokes from student) |
| `shell_stdout` | `{ bytes_b64 }` |
| `shell_stderr` | `{ bytes_b64 }` |
| `lesson_start` | `{ lesson_title }` |
| `lesson_complete` | `{ duration_ms }` |
| `challenge_attempt` | `{ command }` |
| `challenge_pass` | `{ verify_type, evidence }` |
| `challenge_fail` | `{ verify_type, reason }` |
| `hint_used` | `{ hint_text }` |
| `skip_used` | `{ from_panel }` |
| `course_generated` | `{ subject, course_json }` |

A `chat_user` event with `mode="ask"` and no `course_id` is a free-form question (Ask Mode in the main chat). A `chat_user` with `mode="ask"` and a `course_id` is an "Ask Claude" lookup inside a lesson. A `chat_user` with `mode="course"` is a course-generation request. Same table, scope is just additional columns — keeps the timeline reconstructible without branching schemas.

### Why append-only event log
- Terminal replay is free (asciinema-style reconstruction from `shell_stdin/stdout` events).
- Chat replay is free.
- One canonical chronological view per session — no joining across separate tables.
- Adding new event types later doesn't require schema migrations.

---

## Instructor Dashboard

Separate view inside the same app. Hidden behind a PIN gate; the student sees no entry point unless the PIN is entered.

### Authentication
- **PIN**: 4–6 digits, set on first launch. Stored as a salted hash in Keychain.
- **Recovery code**: one-time human-readable code (e.g., `7K2M-9XQP-RB4N`) shown once at setup with explicit "write this down" copy. Stored as a salted hash. If the parent forgets the PIN, the recovery code resets it. No email, no cloud — appropriate for a single-device deployment.
- **Touch ID** (optional, if hardware supports it via paired Magic Keyboard): can unlock the dashboard without typing the PIN.

### Views
1. **Sessions list** — date, duration, # chat messages, courses touched, challenges passed/failed/skipped, hints used.
2. **Session timeline** — single chronological view interleaving Ask-Mode chat, course-generation moments, lesson activity, and terminal I/O. Filter chips: "Ask Mode only", "Course Mode only", "lesson follow-ups only" — useful for scanning what the student is curious about vs. what they worked through.
3. **Terminal replay** — playback control (▶ ⏸ speed) reconstructed from `shell_stdin/stdout` events. Asciinema-style frame timing.
4. **Chat transcript** — full Claude conversation per session, with token usage.
5. **Export** — single-file HTML bundle of a session for sharing or archive.

### Privacy note
SQLite DB is plaintext on disk. Disk-level protection is FileVault (assumed enabled on a fresh M1). No custom DB encryption.

---

## Safety Model

- Sandbox dir is the only writable location for MacOS lessons.
- Default-deny network in the `sandbox-exec` profile; lessons that teach `curl` / `ssh` opt in via `network: true` in the schema.
- Per-command 30-second timeout.
- Destructive-pattern detector (regex for `rm -rf /`, `:(){:|:&};:`, `dd of=/dev/`, etc.) prompts confirmation even inside the sandbox — as a teaching moment, not just defense.
- Linux container is ephemeral and rootless under Podman; `Reset Sandbox` kills and respawns.
- API key never leaves the device (Keychain → Claude API; not written to disk in plaintext, not logged in events).

---

## Container Runtime: Podman as Default

Podman fits this app better than Docker Desktop for these reasons:

| Factor | Podman | Docker Desktop |
|---|---|---|
| License | Apache 2.0 | Paid for orgs >250 employees |
| Install | `brew install podman` | GUI installer + system extension |
| Daemon | Daemonless, rootless | Background daemon |
| M1 support | Native via `podman machine` (Apple Virtualization.framework) | Native (own VM) |
| Disk footprint | ~3 GB | ~5–8 GB |
| CLI | `podman run/exec/...` mirrors Docker | Reference impl |
| Idle resource use | VM can be stopped | Daemon resident |

Both runtimes sit behind a single `ContainerRuntime` Swift protocol so either can be plugged in:

```swift
protocol ContainerRuntime {
    func ensureReady() async throws
    func startSandbox(courseId: String, image: String, network: Bool) async throws -> SandboxHandle
    func exec(_ handle: SandboxHandle, stdin: AsyncStream<Data>) -> PTYStream
    func reset(_ handle: SandboxHandle) async throws
    func destroy(_ handle: SandboxHandle) async throws
}
```

Auto-detect at launch (`which podman` / `which docker`); user-overridable in preferences. If neither is installed, Linux courses are disabled with a clear "Install Podman: `brew install podman`" message. MacOS courses still work.

### Feasibility checks to run during Phase 5
1. `podman machine init --cpus 2 --memory 2048 --disk-size 20` on M1 → boots cleanly.
2. `podman run --rm -it alpine sh` → interactive PTY works.
3. `podman exec -i <id> bash` with stdin streaming.
4. Cold-start time of a stopped machine (lazy-start on first Linux lesson; expected 5–15 s on M1).
5. `--network=none` honored.

---

## Persistence Layout

```
~/Library/Application Support/EngineerAssistant/
├── db.sqlite                              -- sessions + events
├── courses/
│   └── <course-id>.json                   -- generated, cached
├── sandboxes/
│   └── <course-id>/                       -- MacOS sandbox working dirs
└── exports/                               -- HTML session exports
```

Keychain:
- `anthropic_api_key`
- `instructor_pin_hash`
- `instructor_pin_salt`
- `recovery_code_hash`
- `recovery_code_salt`

---

## Build Phases (verifiable goals)

Each phase ends with an explicit verification step. Don't move on without it.

1. **Skeleton + Ask Mode chat + event log scaffolding** → verify: send a message in the chat UI in Ask Mode; Claude responds (streaming, multi-turn within session); both `chat_user` and `chat_assistant` events appear in `events` table with `mode="ask"`; session row exists with `started_at`.
2. **Course Mode (generation + cached)** → verify: toggle to Course Mode; ask "teach me `grep`"; receive valid `Course` JSON via tool-use; render read-only Concept + Demos panels; chat events tagged `mode="course"`; second ask of same subject hits cache (no API call).
3. **MacOS sandbox + embedded terminal + PTY tee** → verify: run `ls`, `pwd`, `touch foo`; output renders in embedded terminal; `shell_stdin`/`shell_stdout` events captured; attempts to `cd ~/Documents` fail (sandbox blocks it).
4. **Challenge verification** → verify: a `grep` challenge auto-detects success when student runs the right command; failure shows hint affordance.
5. **Podman runtime (Docker fallback)** → verify: fresh Mac Mini with `brew install podman` only; a Linux course spawns a container; `apt`/`apk` commands run; `Reset Sandbox` destroys and respawns cleanly.
6. **Standard controls + progress persistence** → verify: quit mid-course, relaunch, resume at the same lesson with sandbox state restored.
7. **Instructor Dashboard** → verify: first-launch PIN setup with recovery code shown once; sessions list populates; timeline view interleaves chat + terminal + lesson events; replay scrubs correctly; HTML export opens in a browser.
8. **Polish** — hints (Claude call with lesson context), lesson-scoped "Ask Claude" sidebar, course library UI, preferences pane.

---

## Open Items (none blocking Phase 1)

- Touch ID unlock — add when hardware is confirmed.
- LLM-as-judge prompt design — defer to Phase 4 when first open-ended challenge appears.
- HTML export styling — defer to Phase 7.
