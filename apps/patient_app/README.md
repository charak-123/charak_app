# patient_app

CHARAK Patient App (Flutter). Light scheme of CHARAK Design System V2.

UI is built from the shared components in `packages/charak_core`. Before changing
any screen read [`design-system/README.md`](../../design-system/README.md) (the spec)
and the root `CLAUDE.md` (the rules and checks). Fonts (Anek) and the brand mark
come from `charak_core`; this app declares none of its own.

```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
flutter analyze
```
