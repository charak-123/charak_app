# Charak legal documents

**The text people sign lives here, in this folder**, one folder per version:

- `2026-10-28/terms-of-use.md`: patients
- `2026-10-28/practitioner-agreement.md`: doctors
- `2026-10-28/privacy-policy.md`: everyone
- `2026-10-28/refund-cancellation-policy.md`: everyone
- `2026-10-28/telemedicine-consent.md`: patients, before their first online consultation

The apps show each document in full and people sign it there (LD-014 in
[`DECISIONS.md`](DECISIONS.md)). Every signature records the version and the SHA-256
fingerprint of the text (`consents.document_sha256`).

## Publishing a new version

1. Copy the latest folder to a new one named for the new version, and edit the text.
   The header at the top of each file sets its type, title, audience and key points.
   Use only what the apps render: `##`/`###` headings, paragraphs, `- ` and `1. `
   lists, two-column tables, `**bold**` and `*italic*`.
2. `python3 docs/legal/publish.py <version> <next migration number>` writes the
   migration. `--check` fails if it is out of date (the backend tests run it too).
3. Apply the migration. The new version is inactive until someone approves it in
   admin → Policies, after reading the full text there.
4. Once approved, everyone it applies to is asked to sign it the next time they open
   the app; the server refuses booking (patients) or accepting a booking (doctors)
   until they do, once `require_legal_acceptance` is on.

Never edit a published folder: the database refuses changes to a published version,
and signatures point at its fingerprint.

## The website

The website (`charak site`, `src/pages/Legal.jsx`) still has the older text, which
differs from these documents (it mentions a platform commission, a full refund for
every cancellation, Navi Mumbai courts and Fly.io hosting) and has no Practitioner
Agreement or Cancellation & Refund Policy page. Update it from these files.

**Status: for legal review. Not legal advice.** A qualified lawyer must review the
text before it is approved for use (D20).

`2026-10-01/`-era drafts (`terms-of-service.md`, `privacy-policy.md`,
`telemedicine-consent.md` in this folder's root) are kept for history only.
