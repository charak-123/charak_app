-- Voice-note summary, per Requirements Document §3.8.
--
-- §3.8 "AI Scope (V1)" is explicit: "Voice → transcription + summary for the
-- doctor only. Nothing diagnostic. Nothing analyzes video or images."
--
-- So the boundary is not "no AI on intake" — it is: AI touches the voice note
-- and nothing else, and it reports what was said rather than what it means. The
-- summary is a reading aid for a doctor scanning a request, not a triage signal.
-- Photos and video are stored and shown as-is; nothing reads them.
--
-- The summary lives beside the transcript rather than replacing it. A doctor
-- must always be able to reach the patient's own words, and the patient can
-- edit the transcript, which the summary must never silently contradict.

alter table intake_media
  add column if not exists transcript_summary text,
  -- Which model produced the summary. When a model is swapped, or a summary is
  -- later disputed, "which one wrote this" is the first question asked.
  add column if not exists summary_model text;

comment on column intake_media.transcript_summary is
  'Short summary of the voice note for the doctor (Requirements Doc 3.8). '
  'Never diagnostic; never generated from images or video.';
