# Use cases — what to actually do with this thing

Every section below is a real workflow with a copy-pasteable prompt and the tools the AI will end up calling. None of these require the destructive-write toggle unless explicitly noted.

---

## 1. Daily standup that writes itself

**The pain:** It's 9:55 AM. The standup starts in 5 minutes. You don't remember what you did Tuesday afternoon, let alone Monday.

**The prompt:**
> Using `recent_projects` and `files_touched` for the last 24 hours, draft me 3 standup bullets in this format: "Yesterday: …", "Today: …", "Blocked on: …". Keep it terse. Today's plan should be inferred from the last file I touched and the open Cursor window from `current_context`.

**Tools used:** `recent_projects`, `files_touched`, `current_context`

**Why it works:** "What I worked on" is exactly the data shape the timeline captures. The AI doesn't have to guess — it reads the FTS5 index.

---

## 2. End-of-week journaling / weekly review

**The pain:** Friday afternoon. Your manager asked for a weekly summary by EOD. You vaguely remember debugging some auth thing on Tuesday.

**The prompt:**
> Give me a weekly review. For each repo I touched in the last 7 days, list: total hours (`time_per_repo`), top 3 files edited (`files_touched`), and one-line guess at what I was working on (look at the file paths). Group by repo, sort by hours descending. End with a "themes" section — what was the through-line of the week?

**Tools used:** `time_per_repo`, `files_touched`, `query_timeline`

**Tip:** Save the result as a markdown file. Over time it becomes a useful personal log — the kind people pay productivity coaches to maintain.

---

## 3. Re-orient after a Slack rabbit hole

**The pain:** You looked up at the clock. It's 3:17 PM. You started "a quick check" at 1:30. What were you actually doing before that?

**The prompt:**
> I lost the thread. Call `current_context` for now, then `query_timeline` for 90 minutes ago. What was I working on, what file, and what was the last meaningful edit? Just tell me where to pick up — no lecture.

**Tools used:** `current_context`, `query_timeline`

---

## 4. Find the file you can't name

**The pain:** "There was a config file I edited last Wednesday for the auth thing, it had `pool` somewhere in the name, I think it was in the API repo."

**The prompt:**
> Search `query_timeline` for window titles matching "pool" or "auth" between last Tuesday and Friday. Sort by frequency. What file paths come up?

**Tools used:** `query_timeline`

**Why it works:** The window-title parser pulls `(repo, file)` out of every IDE title bar. So FTS over titles is effectively FTS over the files you've been in.

---

## 5. PR description from real work

**The pain:** You're about to open a PR and the description is "fixes the bug." You touched 14 files over 3 days and remember about 4 of them.

**The prompt:**
> I'm opening a PR for branch `fix/idle-detection-flakes`. Use `files_touched` filtered to that repo for the last 5 days and group the files by directory. For each group, write one bullet describing what changed (you can look at the file path; don't make up specifics). Output as a markdown PR description with Summary + Changes + Test plan sections.

**Tools used:** `files_touched`, `recent_projects`

---

## 6. Time-box a deep-work session

**The pain:** You want to block out 90 minutes for the auth refactor and have your assistant nudge you if you drift.

**The prompt:**
> I'm starting a 90-min deep-work block on the `auth-refactor` branch in `myapp`. Set a mental bookmark. In 45 minutes ask me how it's going by checking `current_context` — if I'm not in `myapp` anymore, prompt me about it.

**Tools used:** `current_context` (twice)

**Note:** This relies on the AI host running long enough to follow up. Better paired with a rule (see [`examples/rules/`](../examples/rules/)) that fires on `Idle entered for 5 minutes` while the deep-work flag is on.

---

## 7. Idle bloat sweep (writes — requires Actions toggle)

**The pain:** You have 47 apps open, half of them haven't been touched in hours, your battery is at 12%.

**The prompt:**
> List apps with `list_processes` that are over 500 MB and where `query_timeline` shows I haven't focused them in 60+ minutes. For each, ask me one yes/no before calling `kill_app`. Skip anything with unsaved changes (the tool will refuse anyway, just don't ask if you can see the file is dirty).

**Tools used:** `list_processes`, `query_timeline`, `kill_app`

**Safety:** `kill_app` requires the Actions toggle ON (Settings → Actions). Even with it on, the chokepoint enforces a per-bundle 60s cooldown, refuses SIP-protected processes, and bails on dirty windows.

---

## 8. "Why is my computer slow right now?"

**The pain:** Things feel sluggish. You don't know what's hogging RAM.

**The prompt:**
> Call `list_processes` sorted by memory descending. Top 10. For each, tell me when I last actually used it (`query_timeline`). If I haven't touched it in 30+ minutes and it's over 1 GB, suggest closing it.

**Tools used:** `list_processes`, `query_timeline` — read-only, even the suggestion is text

---

## 9. Calendar correlation (if Calendar permission granted)

**The pain:** "I had a meeting with Sarah on Tuesday — what did I work on right after? I think she gave me a TODO."

**The prompt:**
> Find any calendar event on Tuesday with "Sarah" in the attendees or title. For 60 minutes after the event ended, call `query_timeline` and tell me what files I edited. Probably one of them maps to whatever she asked for.

**Tools used:** `query_timeline` (with calendar correlation enabled)

---

## 10. Build a personal Slack-status updater

**The pain:** Your team teases you for "in a meeting" status that's a lie 70% of the time.

**The setup:** A rule (in `examples/rules/`) that watches Focus mode and posts a status update via Shortcuts.

**Why it's interesting:** The rule engine doesn't need the AI in the loop. The AI is for ad-hoc questions; rules are for deterministic reactions. You'd ask the AI to *propose* a rule (`create_rule` write tool) and review it before saving.

---

## 11. "Who pinged me when I was deep in code?"

**The pain:** You missed a Slack DM at 2 PM because you had Focus mode on.

**The prompt:**
> Between 1:30 PM and 3:00 PM today, call `query_timeline` for "slack" or "messages". Did I focus those apps at all, or was I in deep work? Show the gaps.

**Tools used:** `query_timeline`

---

## 12. Auto-document a debugging session

**The pain:** You spent 4 hours fixing a flaky test and you want notes for future-you.

**The prompt:**
> I just fixed something in `myrepo`. Look at the last 4 hours via `files_touched`, `query_timeline`, and `recent_projects`. Reconstruct the path: what files I jumped between, in what order, with rough timestamps. Output as a "debugging trace" markdown — future me wants to remember this if it happens again.

**Tools used:** `files_touched`, `query_timeline`, `recent_projects`

---

## 13. Onboarding a new project

**The pain:** You forked a repo, started exploring, but a week later you're not sure which files are core vs. which you opened by accident.

**The prompt:**
> For repo `<name>`, give me the top 20 files by `files_touched` over the last 14 days. Skip anything I only opened once. The remaining list is roughly the parts of the codebase I've actually engaged with.

**Tools used:** `files_touched`

---

## 14. Distraction audit

**The pain:** "Where is my time going?"

**The prompt:**
> Call `time_per_repo` for the last 7 days, but also include non-repo time (use `query_timeline` to bucket everything by frontmost app). What was the split between coding apps, browsers, chat apps, and everything else?

**Tools used:** `time_per_repo`, `query_timeline`

**Caveat:** This is honest, not flattering. The data does not lie about how long Twitter was frontmost.

---

## 15. Audit log review (security paranoia)

**The pain:** You enabled the Actions toggle a week ago. What has the AI actually done since then?

**The prompt:**
> Pull the last 100 entries from `audit_log`. Show me every write call (kill_app, create_rule, update_rule, delete_rule) with timestamp, calling client, and result. Anything look weird?

**Tools used:** `audit_log`

**Why it matters:** The log is append-only on the local filesystem. The AI cannot delete it (no tool exposes that) and cannot lie about it (you can also `cat` the SQLite db yourself).

---

## Patterns across these use cases

A few recurring shapes:

1. **Recall** — most prompts are read-only. The AI's job is to fetch + summarize, not act.
2. **Grounding** — the system prompt template in the README tells the AI *don't infer activity from chat history; call a tool*. This avoids the classic "I think you were working on…" hallucination.
3. **Confirmation before action** — even with Actions toggle on, every prompt that uses a write tool asks for explicit confirmation. This is convention, not enforced — but the rate limits and audit log mean the cost of a mistake is bounded.
4. **Tool composition** — interesting answers usually come from 2-3 tool calls chained together (`current_context` → `query_timeline` → `files_touched`).

The richest prompts treat the MCP tools the way a senior engineer treats `grep`: a primitive you compose, not a magic answer machine.

---

## Want more?

- The runnable rule examples in [`../examples/rules/`](../examples/rules/) cover automation patterns.
- The `amctl` shell scripts in [`../examples/amctl/`](../examples/amctl/) cover the CLI patterns.
- The MCP fixture JSONs in [`../examples/mcp/`](../examples/mcp/) show what the raw tool I/O looks like — useful when you're debugging your own integration.
