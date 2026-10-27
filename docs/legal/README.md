# Charak legal documents

**The published text lives in the website repo** (`charak site`,
`src/pages/Legal.jsx`) and is served at:

- https://www.charak.care/privacy
- https://www.charak.care/terms
- https://www.charak.care/telemedicine
- https://www.charak.care/disclaimer

Those pages cover the website and both apps. The markdown files in this folder
are the earlier app-only drafts, kept for reference; edit the website, not these.

**Status: DRAFT for legal review. Not legal advice.** A qualified lawyer must
review the text and confirm the retention periods, grievance-officer details and
any state-specific medical-record rules. Fill in the `ENTITY` placeholders at
the top of `Legal.jsx` before launch.

The published versions live in the `legal_documents` table (migration 0024),
and consent is recorded against them in `consents` (append-only, with how it
was given and for which booking). When a document changes materially, publish
the new text on the website, then add a row for the new version
(docs/runbooks/backend_go_live.md §6c). The apps ask everyone again on their
next visit to home, and booking refuses until they accept once the
`require_legal_acceptance` switch is on. The versions are no longer hard-coded
in the apps.

**Decisions** behind these documents (jurisdiction, fees, refunds, retention, and so
on) are recorded in [`DECISIONS.md`](DECISIONS.md). Read it before you change any
legal text.
