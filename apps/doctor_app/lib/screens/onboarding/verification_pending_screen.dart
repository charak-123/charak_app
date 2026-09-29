import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class VerificationPendingScreen extends ConsumerStatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  ConsumerState<VerificationPendingScreen> createState() => _VerificationPendingScreenState();
}

class _VerificationPendingScreenState extends ConsumerState<VerificationPendingScreen> {
  CharakPoller? _poll;
  String _status = 'pending';
  String? _rejectionReason;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Verification is a human decision minutes-to-days away, so this starts
    // slow and eases off to five minutes. Push (`doctor.verified`) is what
    // makes it feel immediate; this only catches a missed notification.
    _poll = CharakPoller(
      onPoll: _refresh,
      interval: const Duration(seconds: 20),
      maxInterval: const Duration(minutes: 5),
    )..start();
  }

  /// Reads the doctor's own profile through the backend.
  ///
  /// A Supabase realtime subscription cannot work here: the app holds only the
  /// anon key and authenticates with a FastAPI JWT, so `auth.uid()` is NULL
  /// and the doctors RLS policy matches no rows. The stream never fired, so a
  /// doctor approved by ops sat on this screen until they restarted the app.
  /// Returns true once ops have approved, which stops the poll. A rejection
  /// keeps polling: ops can reverse it after the doctor re-submits.
  Future<bool> _refresh() async {
    final me = await ApiClient.instance.get('/doctors/me')
        as Map<String, dynamic>;
    if (!mounted) return true;
    final status = me['verification_status'] as String? ?? 'pending';
    setState(() {
      _status = status;
      _rejectionReason = me['verification_rejection_reason'] as String?;
    });
    if (status == 'verified') {
      context.go('/setup/channels');
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _poll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRejected = _status == 'rejected';
    final (badgeBg, badgeFg) = isRejected
        ? charakToneColors(CharakStatusTone.danger)
        : (CharakColors.bgSubtle, CharakColors.inkMuted);

    return Scaffold(
      backgroundColor: CharakColors.ground,
      body: SafeArea(
        // `.ok-state` — 40px top padding, 24px gutters, centred column.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // `.ok-state .wait-ic` — 88px circle, 40px glyph.
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(
                  isRejected ? Icons.cancel_outlined : Icons.assignment_turned_in_outlined,
                  size: 40,
                  color: badgeFg,
                ),
              ),
              const SizedBox(height: 20),
              // `.ok-state .title` at the screen's 21px override.
              Text(
                isRejected ? 'Verification declined' : 'Under review',
                textAlign: TextAlign.center,
                style: CharakText.display.copyWith(fontSize: 21, letterSpacing: -0.21),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  isRejected
                      ? 'We could not verify your credentials. Please check and resubmit.'
                      : "Our team is verifying your license. You can set up your practice now — "
                          "you'll appear in the directory the moment you're approved.",
                  textAlign: TextAlign.center,
                  style: CharakText.body.copyWith(color: CharakColors.inkMuted, fontSize: 15),
                ),
              ),

              if (isRejected && _rejectionReason != null) ...[
                const SizedBox(height: CharakSpacing.base),
                Container(
                  padding: const EdgeInsets.all(CharakSpacing.md),
                  decoration: BoxDecoration(
                    // Spec danger tint — translucent, not an opaque pink.
                    color: charakToneColors(CharakStatusTone.danger).$1,
                    borderRadius: const BorderRadius.all(CharakRadius.card),
                  ),
                  child: Text(
                    'Reason: $_rejectionReason',
                    style: CharakText.caption.copyWith(color: CharakColors.danger),
                  ),
                ),
              ],

              if (!isRejected) ...[
                const SizedBox(height: 18),
                const CharakStatusPill(
                  label: 'Under review',
                  tone: CharakStatusTone.warning,
                  pulsingDot: true,
                ),
                const SizedBox(height: 22),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: CharakButton(
                    label: 'Explore the app',
                    outlined: true,
                    onPressed: () => context.go('/setup/channels'),
                  ),
                ),
                const SizedBox(height: 10),
                const CharakHintLine(
                  text: 'Nothing goes live until ops approves your license.',
                  align: TextAlign.center,
                ),
              ],

              if (isRejected) ...[
                const SizedBox(height: CharakSpacing.xl),
                CharakButton(
                  label: 'Resubmit credentials',
                  onPressed: () => context.go('/onboarding/verification'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
