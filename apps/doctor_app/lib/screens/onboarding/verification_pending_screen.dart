import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:charak_core/charak_core.dart';

class VerificationPendingScreen extends ConsumerStatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  ConsumerState<VerificationPendingScreen> createState() => _VerificationPendingScreenState();
}

class _VerificationPendingScreenState extends ConsumerState<VerificationPendingScreen> {
  String _status = 'pending';
  String? _rejectionReason;

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    final auth  = ref.read(authProvider);
    final doctorId = auth.user?['id'] as String?;
    if (doctorId == null) return;

    Supabase.instance.client
        .from('doctors')
        .stream(primaryKey: ['id'])
        .eq('id', doctorId)
        .listen((rows) {
          if (rows.isEmpty || !mounted) return;
          final row = rows.first;
          final status = row['verification_status'] as String;
          setState(() {
            _status = status;
            _rejectionReason = row['verification_rejection_reason'] as String?;
          });
          if (status == 'verified' && mounted) {
            context.go('/setup/channels');
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final isRejected = _status == 'rejected';
    final (badgeBg, badgeFg) = isRejected
        ? charakToneColors(CharakStatusTone.danger)
        : (CharakColors.bgSubtle, CharakColors.inkMuted);

    return Scaffold(
      backgroundColor: CharakColors.bg,
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
                  style: const TextStyle(
                    fontFamily: CharakText.fontFamily,
                    fontSize: 14.5,
                    height: 1.6,
                    color: CharakColors.inkMuted,
                  ),
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
