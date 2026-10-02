# Charak legal documents

**Status: DRAFT for legal review. Not legal advice.** These are first drafts
prepared to cover App Store / Play and India DPDP + Telemedicine Practice
Guidelines 2020 requirements. A qualified lawyer must review and finalise them,
and confirm the retention periods, grievance-officer details and any
state-specific medical-record rules before publication.

Replace every `[BRACKETED]` placeholder. Host the finalised versions at stable
public URLs and set these in the apps:

- `privacyPolicyUrl` / `termsUrl` / `telemedicineConsentUrl` in
  `packages/charak_core/lib/legal.dart`.

When a document changes materially, bump its version in `backend/app/config.py`
(`LEGAL_*_VERSION`); the apps then re-request consent and record the new version.
