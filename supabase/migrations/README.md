# Migrations

Applied by hand in the Supabase SQL Editor, in numeric order — see
`docs/runbooks/backend_go_live.md`. Each file is written to be idempotent
(`if not exists` / `if exists`) so re-running one is harmless.

**0005 does not exist.** The numbering jumps from `0004_rls.sql` to
`0006_phase2_columns.sql`; nothing was ever written as 0005, and no migration
was deleted. Numbers are not reused — the next one is `0021`.
