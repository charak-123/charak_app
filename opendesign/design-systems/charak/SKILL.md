# CHARAK Design System

Design system for CHARAK — home-visit & online-consult appointment booking platform (Patient App + Doctor App). V1 direction: *Premium Banking* — white + soothing blue `#2F6FED`, Inter, hairline borders, single-accent restraint.

Source: `CHARAK_Prototype_Reference.md` (§1 design tokens, §1.4 motion) + `CHARAK_App_Requirements_Document.docx`.

## Tokens

See `colors_and_type.css` — the canonical token file:

- **Colors** (11): `--color-bg #FFFFFF`, `--color-bg-subtle #F5F8FA`, `--color-primary #2F6FED`, `--color-primary-soft #EAF1FE`, `--color-primary-deep #1E4FBF`, `--color-ink #101828`, `--color-ink-muted #5B6472`, `--color-border #E4E8EE`, `--color-success #1FAA6D`, `--color-warning #E0930B`, `--color-danger #E0473E`. Desaturated status colors sit quietly next to the blue — no traffic lights.
- **Type**: Inter throughout; weight differentiates. Display 28/600, H1 22/600, H2 17/600, Body 15/400, Body-Med 15/500, Caption 13, Micro 11/500 uppercase +0.04em. Tabular figures for prices/times/OTP (`.tnum`).
- **Shape**: 4px spacing grid; radius 12 cards / 10 controls / pill chips/badges; soft shadows only (`0 2px 8px` resting, `0 8px 24px` sheets). Never border + shadow on the same surface.
- **Touch targets**: ≥44×44px.

## Motion (confirming, not decorative)

| Interaction | Spec |
|---|---|
| Push transition | slide from right + fade, 280ms ease-out |
| Sheet/modal | slide up + backdrop fade, 240ms ease-out |
| Button press | scale 0.97 + opacity 0.9, 100ms |
| Status change | cross-fade + primary-soft highlight pulse, 600ms |
| Success (accept/payment) | checkmark draw-in, scale 0.9→1 spring, 400ms |
| Loading | skeleton shimmer, never spinners for known shapes |
| New request (doctor) | card slides in from top, 320ms |

No bounce/spin for delight; the one expressive moment is booking-accepted / payment-success.

## Rules

- No gradients, no glassmorphism, no colored left-border card accents.
- Cards: white fill, 1px border **or** soft shadow — not both.
- Status badges always paired with text, never color-only.
- Doctor App shares all tokens but has its own shell: ink (`#0E1525`) tab bar + chrome — sibling, not twin (Uber rider vs driver).
