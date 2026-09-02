import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

class RateScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const RateScreen({super.key, required this.bookingId});
  @override
  ConsumerState<RateScreen> createState() => _State();
}

class _State extends ConsumerState<RateScreen> {
  int _stars = 0;
  final _commentCtrl = TextEditingController();
  bool _loading = false;
  bool _submitted = false;

  Future<void> _submit() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiClient.instance.post('/bookings/${widget.bookingId}/rate', {
        'stars': _stars,
        'comment': _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
      });
      if (mounted) setState(() => _submitted = true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: CharakColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CharakColors.bg,
    appBar: AppBar(
      title: const Text('Rate Your Experience'),
      backgroundColor: CharakColors.bg,
      foregroundColor: CharakColors.ink,
      elevation: 0,
    ),
    body: _submitted ? _SuccessBody() : _RateBody(),
  );

  Widget _SuccessBody() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(CharakSpacing.lg),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Spacer(),
        const Icon(Icons.favorite, color: CharakColors.danger, size: 72),
        const SizedBox(height: 24),
        Text('Thank you!', style: CharakText.display),
        const SizedBox(height: 8),
        Text(
          'Your feedback helps other patients find great doctors.',
          style: CharakText.body.copyWith(color: CharakColors.inkMuted),
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        CharakButton(label: 'Go Home', onPressed: () => context.go('/home')),
        const SizedBox(height: 24),
      ]),
    ),
  );

  Widget _RateBody() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(CharakSpacing.base),
      child: Column(children: [
        const SizedBox(height: 24),
        Text('How was your experience?', style: CharakText.h1),
        const SizedBox(height: 8),
        Text(
          'Rate the quality of care you received.',
          style: CharakText.body.copyWith(color: CharakColors.inkMuted),
        ),
        const SizedBox(height: 32),
        // Star row
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) {
          final filled = i < _stars;
          return GestureDetector(
            onTap: () => setState(() => _stars = i + 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                filled ? Icons.star : Icons.star_border,
                color: filled ? const Color(0xFFFFB800) : CharakColors.border,
                size: 44,
              ),
            ),
          );
        })),
        const SizedBox(height: 8),
        Text(
          _stars == 0 ? 'Tap to rate' : _starLabel(_stars),
          style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _commentCtrl,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Share more details (optional)…',
          ),
        ),
        const Spacer(),
        CharakButton(
          label: 'Submit Rating',
          isLoading: _loading,
          onPressed: _stars > 0 ? _submit : null,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go('/home'),
          child: const Text('Skip'),
        ),
        const SizedBox(height: 24),
      ]),
    ),
  );

  String _starLabel(int stars) {
    const labels = ['', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent'];
    return labels[stars];
  }
}
