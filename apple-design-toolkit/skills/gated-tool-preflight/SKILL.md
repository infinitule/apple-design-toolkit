---
name: gated-tool-preflight
description: Satisfy policy hooks that gate tool calls (fact-forcing preambles, destructive-command confirmation, first-call declarations) on the FIRST attempt instead of failing and retrying — and recognise the unconditional gates that no preamble can satisfy. Use whenever a hook blocks a Bash/Write/Edit call demanding justification.
---

# Preflight for Gated Tools

Some harnesses wrap tools in policy hooks that reject a call and demand a declaration first. The expensive failure mode is **fail → read the demand → retry the identical call**, repeated all session because nothing was learned from the first denial.

Two kinds of gate exist, and they need opposite responses. Diagnosing which one you face is the whole skill.

## Step 1: classify the gate

**Content-checking gates** read your message and pass once the required declaration is present. Preamble prevents the denial entirely.

**Unconditional speed bumps** fire on the *first* occurrence of a trigger (first Bash of the session, first write to a given path) regardless of what you wrote. The retry succeeds with byte-identical input. No preamble can prevent them.

**How to tell them apart:** on denial #1, add the declaration and retry. If a subsequent *different* first-touch is denied even though you declared everything up front, it is unconditional. Test once — then stop trying to out-argue it.

## Step 2A: content-checking gate → declare first

Emit the declaration as assistant text immediately before the call, in the same turn. Answer concretely:

- **Callers:** name the file and mechanism (`run by the next Bash step via swift images.swift`), or state plainly there are none.
- **No duplicate:** what you checked, and what the nearest existing file does differently.
- **Data:** real field names and formats; synthetic values only.
- **Rollback:** an actual command (`git checkout -- main.swift`), not "revert if needed".
- **Verbatim instruction:** quote the user, don't paraphrase.

Batch them: four gated writes coming up → one preamble covering all four, then all four calls.

## Step 2B: unconditional gate → reduce the trigger count

Arguing with it is pure waste. Lower how many times it can fire:

- **Fewer new files.** Extend an existing file instead of creating a sibling. One `images.swift` with nine functions costs one gate; nine files cost nine.
- **Fewer, larger Bash calls.** Build + deploy + verify in one command, not six.
- **Avoid destructive syntax** when an equivalent exists: `OUT=$(mktemp -d)` trips nothing, `rm -rf /tmp/x && mkdir` trips the destructive gate every time.
- **Don't re-read** a file you just wrote; the write already confirmed it.
- **One patch, not many edits:** a single `python3 -` heredoc doing N replacements beats N `Edit` calls.
- **Surface the escape hatch.** These hooks document a disable path (`ECC_GATEGUARD=off`, or adding the hook id to `ECC_DISABLED_HOOKS`). If the gate is obstructing legitimate work at volume, tell the user that option exists and let them decide — do not silently absorb the cost for a hundred calls.

## Step 3: never resend an identical call blind

After a denial, either add the missing element (content gate) or accept the retry is the cost of entry (speed bump). What you must not do is retry identically *while believing you fixed something* — that is how a session accumulates dozens of duplicate payloads.

Keep a running ledger of which triggers have fired. Assume per-path and per-session-per-family scope, not once-ever.

## Why this is worth doing beyond tokens

A gate that keeps firing is signal. It usually means the change is touching more new files, or more destructive commands, than the task actually warrants. Declaring intent up front tends to reveal the smaller change you should have made instead.
