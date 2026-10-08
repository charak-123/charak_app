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

The apps link to these URLs through `CharakLegal` in
`packages/charak_core/lib/legal.dart` (overridable with `--dart-define`).
When a document changes materially, bump its version there and in
`backend/app/config.py` (`LEGAL_*_VERSION`); the apps then re-request consent
and record the new version.
