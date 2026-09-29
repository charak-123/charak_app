# CHARAK: notes for contributors and coding agents

Monorepo: `apps/patient_app` + `apps/doctor_app` (Flutter), `packages/charak_core`
(shared Flutter package), `admin/` (React + Vite + Tailwind v3 + shadcn),
`backend/` (FastAPI), `supabase/` (SQL), `opendesign/` (HTML mockups).

## UI / UX: always follow the design system

**`design-system/README.md` is the spec (CHARAK Design System V2).** Read it before
touching any UI. The short version:

- Values live only in `design-system/tokens.json`. After editing it run
  `python3 design-system/tool/generate.py`. Never edit `tokens.g.dart`,
  `admin/src/styles/charak-tokens.css` or `opendesign/design-systems/charak/colors_and_type.css`.
- Patient app = light scheme (cream ground, white cards). Doctor app = ink scheme
  (`CharakColors.useScheme(CharakScheme.doctor)` in `main.dart`). Screens read
  **role** colours (`CharakColors.ground/card/ink/inkMuted/primary…`) so shared
  code works in both. No hex literals, no `BoxShadow`, no `Colors.white` fills,
  no `TextStyle(fontFamily: …)` in screens.
- Blue acts (everything tappable), Chandan welcomes (greetings, ratings, the
  wordmark, "Requested"), never a Chandan button.
- Type: Anek via `CharakText.*` (display/title.* are wide). Numbers use `.tabular`.
- Layout: big title in the top third, actions in the lower two-thirds. Tab roots use
  `CharakLargeTitleScaffold`; pushed screens use `CharakTopBar` + `CharakCtaBar`;
  confirmations use `showCharakConfirm` (a sheet).
- Flat: 26px cards, 20px tiles/fields, pill buttons ≥ 52px, no shadows.
- Motion only from `CharakMotion` / `CharakCurves` (≤ 450ms, press = scale 0.96,
  honour `charakReduceMotion`).
- Reuse components from `packages/charak_core/lib/components/` (catalogue in
  README §7). Add new shared widgets there and to `lib/gallery.dart`.

## Checks before committing UI work

```bash
python3 design-system/tool/generate.py --check
(cd packages/charak_core && flutter analyze && flutter test)
(cd apps/patient_app && flutter analyze)
(cd apps/doctor_app && flutter analyze)
(cd admin && npm run build)
```

If a shared component changed visually, refresh the goldens
(`cd packages/charak_core && flutter test --update-goldens test/gallery_golden_test.dart`)
and commit `design-system/screenshots/*.png`.
