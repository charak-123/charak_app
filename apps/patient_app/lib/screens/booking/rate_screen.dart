import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../home/booking_providers.dart';

const _starLabels = ['Tap a star', 'Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

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

  void _toHistory() {
    ref.read(homeTabIndexProvider.notifier).state = 2;
    context.go('/home');
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CharakColors.bg,
    appBar: const CharakTopBar(title: 'Rate your visit'),
    body: _submitted ? _success() : _form(),
  );

  Widget _success() => Column(children: [
    Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 34, 20, 24),
        child: Column(children: [
          const CharakOutcomeState(
            title: 'Thanks for rating!',
            message: 'Your feedback helps other patients pick the right '
                'doctor for them.',
          ),
          const SizedBox(height: 20),
          CharakStarRating(value: _stars, size: 22, gap: 6),
        ]),
      ),
    ),
    CharakCtaBar.single(
      CharakButton(label: 'Done', onPressed: _toHistory),
    ),
  ]);

  Widget _form() => Column(children: [
    Expanded(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
        children: [
          const Text('How was your visit?',
              style: charakScreenTitleStyle, textAlign: TextAlign.center),
          const SizedBox(height: 5),
          const Text('Only the stars are required — the comment is optional.',
              style: charakScreenSubStyle, textAlign: TextAlign.center),

          // `.stars` — 26px above, 8px below, 40px glyphs.
          Padding(
            padding: const EdgeInsets.only(top: 26, bottom: 8),
            child: CharakStarRating(
              value: _stars,
              onChanged: (v) => setState(() => _stars = v),
            ),
          ),

          // `.rate-hint`
          Text(_starLabels[_stars],
              textAlign: TextAlign.center,
              style: CharakText.caption.copyWith(
                  fontSize: 13.5, color: CharakColors.inkMuted)),
          const SizedBox(height: 18),

          CharakField(
            label: 'Add a comment (optional)',
            controller: _commentCtrl,
            placeholder: 'What should other patients know?',
            maxLines: null,
            minLines: 4,
          ),
        ],
      ),
    ),
    CharakCtaBar(children: [
      Expanded(
        child: CharakButton(label: 'Skip', outlined: true, onPressed: _toHistory),
      ),
      Expanded(
        child: CharakButton(
          label: 'Submit rating',
          isLoading: _loading,
          onPressed: _stars > 0 ? _submit : null,
        ),
      ),
    ]),
  ]);
}
