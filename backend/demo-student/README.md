# demo-student

A local companion service that lets a teacher **simulate an incoming student
question** from inside the app. The question text — and every follow-up message
the "student" sends during the session — is written by a **local AI model**
(Qwen via Ollama by default), so nothing leaves the machine running this service
and no real student is involved.

It is the mirror image of [`../ai-teacher`](../ai-teacher): that service plays
the teacher, this one plays the student.

```
Teacher app                 RTDB                     demo-student            RTDB / Firestore
────────────                ────                     ────────────            ────────────────
"Simulate question"  ──►  demoStudent/requests  ──►  generate question  ──►  questions/{qid}
                                                     (local Qwen)            teacherInvites/{teacher}/{qid}
                            ◄── status/questionId ──                         ─► invite lands in the app

Teacher accepts and chats ──►  questions/{qid}/messages  ──►  student reply (local Qwen) ──► back into the chat
```

## Who answers a simulation

The app never writes the request itself — it calls the `simulateDemoQuestion`
Cloud Function, which checks whether this service is online (see
`demoStudent/service` below) and routes accordingly:

| This service | What happens |
| --- | --- |
| **online** | The function queues the request here, and everything below applies: a real question from the local model, and in-character replies during the chat. |
| **offline** | The function creates the question itself from the `demo_student_offline_message` Remote Config string, and a Firestore trigger answers the teacher with the same message. The invite/accept/chat flow still demos with nothing running locally. |

The canned message carries a counter that runs across one demo: the question is
`#1`, then each reply is `#2`, `#3`… `{count}` in the template is where the
number goes (`demo_student_offline_message_he` holds the Hebrew variant):

```
This is an automatic message from Demo #{count}
```

## What it does

1. Watches `demoStudent/requests` in the Realtime Database. The
   `simulateDemoQuestion` function writes one node per tap on **Simulate
   student question** — but only while this service is online.
2. Asks the local model for a realistic question in the requested topic,
   difficulty and language.
3. Tops up the demo student's Firestore user doc (so the lesson is not blocked
   on "not enough time left") and creates the question exactly the way
   `createQuestion` does: RTDB `questions/{qid}` first, then the Firestore doc.
4. Invites **only the teacher who asked for the simulation** — the question is
   flagged `isDemo: true`, and `dispatchQuestion` skips fan-out for demo
   questions so no real teacher is ever paged by a simulation.
5. After the teacher accepts, plays the student in the chat: every teacher
   message gets a short, in-character reply from the local model, until the
   student says it understood, the reply budget runs out, or the session ends.

## Setup

```bash
# 1. A local model. Qwen 2.5 7B is a good default; qwen2.5:3b is fine on a laptop.
ollama pull qwen2.5:7b

# 2. Config
cd backend/demo-student
cp .env.example .env
$EDITOR .env        # service account path + FIREBASE_DATABASE_URL

# 3. Run
npm install
npm run dev         # or: npm start
```

On startup the service pings the model and prints whether it answered. If the
model is unreachable it keeps running and falls back to a canned question per
topic (turn that off with `DEMO_STUDENT_ALLOW_FALLBACK=false`).

Everything is configured through `.env` — see `.env.example` for the full list,
including the model name, the demo student's identity, the reply delay and the
per-session reply cap.

## Running it against the app

1. Deploy the updated Realtime Database rules (they allow a signed-in teacher to
   write their own `demoStudent/requests/{id}` node):
   `firebase deploy --only database`
2. Deploy the functions if you want demo questions kept away from real teachers:
   `firebase deploy --only functions`
3. Start this service on your machine.
4. In the app, sign in as a teacher, go online, and use **Simulate student
   question** on the dashboard. The invite arrives like any other one.

## Turning the feature on and off

`demo_student_enabled` in Remote Config is the master switch, read by both the
app and the backend:

| Flag | App | Backend |
| --- | --- | --- |
| `true` | The Demo Mode card is shown | Simulations allowed |
| `false` | Card hidden | `simulateDemoQuestion` refuses, and canned replies stop — including mid-session |
| not published | Shown in `DEBUG` builds, hidden in release | Allowed, so an existing setup keeps working |

Two caveats on timing: the app caches Remote Config for up to an hour, so a
teacher may still see the button briefly after you switch it off — the callable
refuses and the dashboard says the feature is turned off. The backend caches the
template for five minutes.

## Troubleshooting

**The request appears under `demoStudent/requests` but nothing shows up under
`questions/`.** Nothing consumed the request. Look at the request node's
`status` field — it tells you where it stopped:

| `status` | What it means |
| --- | --- |
| `pending` | The service never picked it up: it stopped between the presence check and the request, is pointed at another database, or the request was older than `DEMO_STUDENT_REQUEST_MAX_AGE_SECONDS`. The console prints a `skip <id>` line with the exact reason. |
| `generating` | The service took it but died mid-way — check the console for the stack trace. |
| `failed` | The `error` field on the node carries the message (bad credentials, Firestore not reachable, model failure with fallbacks off). |
| `dispatched` | The question was created. `questionId` points at it, and the invite is under `teacherInvites/{teacherUid}/{questionId}`. |

The service publishes its own presence at `demoStudent/service`. When it is
running that node reads `status: "online"` (and flips to `offline` when the
process exits or the connection drops). `simulateDemoQuestion` reads it to
decide between the local model and the canned Remote Config message, so a
stopped service degrades the demo instead of breaking it.

**Getting canned messages when you expected the local model.** The presence node
says `offline` — the service is not running, crashed, or is writing to a
different database than the one the functions read.

## Notes

- Demo questions carry `isDemo: true` (and `demoTeacherUid`) on both the RTDB
  node and the Firestore doc. Lessons started from them inherit `isDemo: true`,
  so demo traffic can be filtered out of reporting later.
- The 90 s invite watchdog still applies: accept the simulated question within
  90 seconds or it is archived as `unanswered`, exactly like a real one.
- Fallback questions additionally carry `demoFallback: true`. The auto-reply
  trigger only answers those, so it never talks over this service.
- If this service dies mid-session, the chat goes quiet: the trigger stays out
  of questions the local model started. Restart the service and simulate again.
- If `ai-teacher` is running at the same time, it ignores demo questions unless
  it is started with `ANSWER_DEMO_QUESTIONS=true` — otherwise it would grab the
  question before the human teacher could.
- Audio/video simulations create the invite, but the demo student only speaks in
  text; use the text conversation type for a full end-to-end demo.
