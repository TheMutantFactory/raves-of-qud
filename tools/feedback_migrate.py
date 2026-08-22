#!/usr/bin/env python3
"""Bring PRE-ENVELOPE feedback records up to envelope v1 so they can be submitted.

Reports filed before 2026-08-10 carry no `v`, `app`, `app_version`, `platform` or `install_id`,
so the server refuses them (400) and the client parks them in `feedback.jsonl.rejected` — which is
the outbox behaving correctly: a report the server will never accept must not be retried forever,
and must not be silently dropped either. This is the other half of that contract, the part that
gets them un-stuck.

WHAT IT WILL NOT DO IS GUESS. `app_version` is genuinely unknown for these — they predate the
field, and stamping them with today's version would put a lie in the one column whose whole job is
to pin a report to a build. They go out as "pre-0.8", which is true and sorts sensibly.

`shot_attached` is the one field here that is DERIVED rather than defaulted, and it is worth knowing
why: these records predate it, absent reads as false, and the submitter decides whether to upload
from `shot` instead — so the first run of this tool put 28 reports in the store flagged "no
screenshot" that then uploaded one. The file on disk is the only thing that settles it, so this asks
the file.

    python3 tools/feedback_migrate.py            # report what would move
    python3 tools/feedback_migrate.py --apply    # move it back into the outbox
"""
import argparse
import json
import os
import sys

SUPPORT = os.path.expanduser("~/Library/Application Support/RavesOfQud")
REQUIRED = ("v", "app", "app_version", "platform", "install_id", "ts")


def install_id():
    p = os.path.join(SUPPORT, "install_id.txt")
    if os.path.exists(p):
        got = open(p).read().strip()
        if got:
            return got
    return "unknown"


# Which overrides slot a verdict belongs in. MIRRORS godot/TileReport.gd `_rule_slot` -- the two
# have to agree or a migrated report and a freshly filed one would describe the same verdict
# differently, and grouping on the sentence would split.
def rule_slot(verdict):
    v = verdict.lower()
    if "effect:" in v or "glow" in v:
        return "effect"
    if "pos:" in v:
        return "position"
    if "fill" in v:
        return "fill"
    for k in ("wall", "panel", "n\u2013s", "e\u2013w", "billboard", "flat", "not be drawn"):
        if k in v:
            return "shape"
    return ""


def upgrade(rec, iid, base):
    out = dict(rec)
    out.setdefault("v", 1)
    out.setdefault("app", "Raves of Qud")
    # Not today's version. See the module docstring.
    out.setdefault("app_version", "pre-0.8")
    out.setdefault("platform", "macOS")
    out.setdefault("install_id", iid)

    # DERIVED, NOT DEFAULTED. `shot_attached` is the field the server stores, and these records
    # predate it entirely -- so the first run of this tool sent 28 reports flagged "no screenshot"
    # that then uploaded one, because the submitter decides from `shot` and the server records the
    # flag. setdefault would repeat that exactly: absent stays absent, and absent reads as false.
    # The file on disk is the only thing that settles it, so ask the file. Same rule as
    # FeedbackSubmitter._resolve_shot, including demoting a claim with nothing behind it: a
    # zero-byte PNG is a failed save, and a promise nobody can check is worse than a plain no.
    # A VERDICT-ONLY REPORT IS NOT AN EMPTY ONE. The tile form accepts "pick a verdict or write a
    # note", so a submit with only a verdict is complete locally -- but it went out with `text: ""`,
    # which the contract forbids, so the server refused it and the outbox parked it here. The
    # verdict is what the reporter actually said, so it becomes the note, WORD FOR WORD the way
    # TileReport._submit now composes it, or the two halves would disagree about what a migrated
    # report says versus a freshly filed one.
    if not str(out.get("text", "")).strip():
        verdict = str(out.get("verdict", "")).strip()
        if verdict:
            out["text"] = "%s: %s" % (rule_slot(verdict) or "rule", verdict)

    rel = str(out.get("shot", "") or "")
    path = os.path.join(base, rel) if rel else ""
    have = bool(path) and os.path.isfile(path) and os.path.getsize(path) > 0
    out["shot_attached"] = have
    if not have:
        out.pop("shot", None)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--rejected", default=os.path.join(SUPPORT, "feedback.jsonl.rejected"))
    ap.add_argument("--outbox", default=os.path.join(SUPPORT, "feedback.jsonl"))
    a = ap.parse_args()

    if not os.path.exists(a.rejected):
        sys.exit("nothing to migrate: %s" % a.rejected)

    recs, bad = [], 0
    for line in open(a.rejected):
        line = line.strip()
        if not line:
            continue
        try:
            recs.append(json.loads(line))
        except json.JSONDecodeError:
            bad += 1

    iid = install_id()
    # Relative `shot` paths resolve against the OUTBOX's directory, because that is where the
    # submitter resolves them from (`outbox_path.get_base_dir()`). Deriving it from the flag rather
    # than hardcoding SUPPORT keeps a custom --outbox honest instead of quietly wrong.
    base = os.path.dirname(os.path.abspath(a.outbox))
    up = [upgrade(r, iid, base) for r in recs]
    # A record with a note the server would still refuse is worth NAMING, not quietly re-queuing
    # into a loop: it would come straight back to .rejected and look like the migration failed.
    empty = [r for r in up if not str(r.get("text", "")).strip()]
    ready = [r for r in up if str(r.get("text", "")).strip()]

    print("%d record(s) in %s" % (len(recs), os.path.basename(a.rejected)))
    if bad:
        print("  %d unparseable line(s) left alone" % bad)
    if empty:
        print("  %d with an empty note -- the server requires one; left in place" % len(empty))
    # Say the version they will ACTUALLY carry. This line was hardcoded to "pre-0.8" from when the
    # only thing parked here was pre-envelope, and it now also catches records that are merely
    # missing a note -- which keep their own real version, so the old text was simply untrue about
    # them. `setdefault` never overwrote it; only the message claimed otherwise.
    vers = sorted({str(r.get("app_version", "?")) for r in ready})
    print("  %d ready to re-queue (app_version %s)" % (len(ready), ", ".join(vers) or "-"))
    repaired = sum(1 for before, after in zip(recs, up)
                   if not str(before.get("text", "")).strip()
                   and str(after.get("text", "")).strip())
    if repaired:
        print("    %d had no note and take their VERDICT as the note" % repaired)
    shots = sum(1 for r in ready if r.get("shot_attached"))
    # Counted against the ORIGINALS: `upgrade` drops the dangling key, so by then the record no
    # longer remembers it ever named a file.
    lost = sum(1 for before, after in zip(recs, up)
               if str(before.get("shot", "") or "").strip() and not after.get("shot_attached"))
    if shots:
        print("    %d of them with a screenshot on disk" % shots)
    if lost:
        print("    %d named a screenshot that is missing or empty -- going out without it" % lost)

    if not a.apply:
        print("\n(dry run -- pass --apply to move them into the outbox)")
        return

    with open(a.outbox, "a") as f:
        for r in ready:
            f.write(json.dumps(r) + "\n")
    keep = empty
    with open(a.rejected, "w") as f:
        for r in keep:
            f.write(json.dumps(r) + "\n")
    print("\nmoved %d into the outbox; %d left in .rejected" % (len(ready), len(keep)))
    print("Raves flushes on start and after each new report.")


if __name__ == "__main__":
    main()
