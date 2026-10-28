-- ═══════════════════════════════════════════════════════════════════════════
-- 0030: the full text of each legal document, read and signed in the apps.
--
--   legal_documents.body        the exact text people accept (a small markdown
--                               subset: ## and ### headings, paragraphs, - and
--                               1. lists, two-column tables, **bold**)
--   legal_documents.summary     one line for the list of documents
--   legal_documents.highlights  the key points, shown above the full text
--   legal_documents.sha256      set by the database from the body, so the
--                               fingerprint always matches the text
--   consents.document_sha256    the fingerprint of the text a person accepted
--   refund_policy               the Cancellation & Refund Policy, a document of
--                               its own that patients and doctors sign
--
-- Rows stay append-only (0024): a change is a new version, and a new version
-- applies only once approved (the review gate, 0029). The text comes from
-- docs/legal/<version>/*.md through docs/legal/publish.py (0031 onwards).
--
-- Idempotent: safe to re-run in the SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════════

alter table legal_documents
  add column if not exists body       text,
  add column if not exists summary    text,
  add column if not exists highlights jsonb not null default '[]'::jsonb;

alter table legal_documents drop constraint if exists legal_documents_type_check;
alter table legal_documents add constraint legal_documents_type_check
  check (type in ('tos', 'privacy', 'telemedicine', 'practitioner_terms', 'refund_policy'));

alter table legal_documents drop constraint if exists legal_documents_highlights_array;
alter table legal_documents add constraint legal_documents_highlights_array
  check (jsonb_typeof(highlights) = 'array');

-- The fingerprint is the database's to set, never the caller's.
create or replace function legal_document_fingerprint()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.sha256 := case when new.body is null then null
                     else encode(sha256(convert_to(new.body, 'UTF8')), 'hex') end;
  return new;
end;
$$;

drop trigger if exists trg_legal_documents_fingerprint on legal_documents;
create trigger trg_legal_documents_fingerprint
  before insert on legal_documents
  for each row execute function legal_document_fingerprint();

alter table consents drop constraint if exists consents_type_check;
alter table consents add constraint consents_type_check
  check (type in ('tos', 'privacy', 'telemedicine', 'marketing', 'practitioner_terms',
                  'booking_policy', 'refund_policy'));

alter table consents add column if not exists document_sha256 text;

notify pgrst, 'reload schema';
