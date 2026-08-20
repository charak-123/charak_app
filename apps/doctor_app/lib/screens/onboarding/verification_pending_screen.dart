import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

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

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CharakSpacing.base),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Illustration
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: isRejected ? const Color(0xFFFEECEB) : CharakColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRejected ? Icons.cancel_outlined : Icons.hourglass_top_rounded,
                  size: 40,
                  color: isRejected ? CharakColors.danger : CharakColors.primary,
                ),
              ),
              const SizedBox(height: CharakSpacing.lg),

              Text(
                isRejected ? 'Verification declined' : 'Under review',
                style: CharakText.h1.copyWith(color: CharakColors.ink),
              ),
              const SizedBox(height: CharakSpacing.sm),

              Text(
                isRejected
                    ? 'We could not verify your credentials. Please check and resubmit.'
                    : 'We\'re reviewing your credentials.\nThis typically takes 24-48 hours.',
                style: CharakText.body.copyWith(color: CharakColors.inkMuted),
                textAlign: TextAlign.center,
              ),

              if (isRejected && _rejectionReason != null) ...[
                const SizedBox(height: CharakSpacing.base),
                Container(
                  padding: const EdgeInsets.all(CharakSpacing.md),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEECEB),
                    borderRadius: BorderRadius.all(CharakRadius.card),
                  ),
                  child: Text(
                    'Reason: $_rejectionReason',
                    style: CharakText.caption.copyWith(color: CharakColors.danger),
                  ),
                ),
              ],

              if (!isRejected) ...[
                const SizedBox(height: CharakSpacing.xl),
                // Pulsing indicator
                _PulsingDot(),
                const SizedBox(height: CharakSpacing.sm),
                Text('Waiting for verification…',
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              ],

              const SizedBox(height: CharakSpacing.xl),

              if (isRejected)
                CharakButton(
                  label: 'Resubmit Credentials',
                  onPressed: () => context.go('/onboarding/verification'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _anim  = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: 12, height: 12,
      decoration: const BoxDecoration(color: CharakColors.warning, shape: BoxShape.circle),
    ),
  );
}
