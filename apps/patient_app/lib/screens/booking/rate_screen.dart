import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../home/booking_providers.dart';

const _starLabels = ['Tap a star', 'Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

/// The patient's review of a finished visit (backend services/reviews.py):
/// whether they can still write one, and if they already have, what it says.
final _reviewProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  return await ApiClient.instance.get('/bookings/$id/review') as Map<String, dynamic>;
});

/// Reviewing a visit: an overall rating (required), three optional questions
/// and an optional comment. Open for 14 days after the visit; a posted review
/// can be changed for 48 hours. Nothing here asks the patient to judge the
/// treatment itself.
class RateScreen extends ConsumerWidget {
  final String bookingId;
  const RateScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_reviewProvider(bookingId));
    return async.when(
      loading: () => const CharakScreen(body: SingleChildScrollView(child: CharakSkeletonDetail())),
      error: (e, _) => CharakScreen(
        body: CharakErrorState(error: e, onRetry: () => ref.invalidate(_reviewProvider(bookingId))),
      ),
      data: (data) {
        final review = data['review'] as Map<String, dynamic>?;
        final editable = review != null &&
            (DateTime.tryParse(review['editable_until'] as String? ?? '')?.isAfter(DateTime.now()) ?? false);
        if (review == null && data['can_review'] != true) {
          return const CharakScreen(
            body: Center(
              child: CharakEmptyState(
                icon: LucideIcons.star,
                title: 'Reviews are closed',
                message: 'A visit can be reviewed for 14 days after it\'s complete.',
              ),
            ),
          );
        }
        return _ReviewForm(bookingId: bookingId, existing: review, editable: review == null || editable);
      },
    );
  }
}

class _ReviewForm extends ConsumerStatefulWidget {
  final String bookingId;
  final Map<String, dynamic>? existing;
  final bool editable;
  const _ReviewForm({required this.bookingId, required this.existing, required this.editable});

  @override
  ConsumerState<_ReviewForm> createState() => _State();
}

class _State extends ConsumerState<_ReviewForm> {
  late int _stars = (widget.existing?['overall'] as num?)?.toInt() ?? 0;
  late final Map<String, int> _dims = {
    for (final k in charakReviewDimensions.keys) k: (widget.existing?[k] as num?)?.toInt() ?? 0,
  };
  late final _commentCtrl = TextEditingController(text: widget.existing?['comment'] as String? ?? '');
  bool _loading = false;
  bool _submitted = false;

  bool get _editing => widget.existing != null;

  Future<void> _submit() async {
    setState(() => _loading = true);
    final body = {
      'overall': _stars,
      for (final e in _dims.entries) e.key: e.value == 0 ? null : e.value,
      'comment': _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
    };
    try {
      if (_editing) {
        await ApiClient.instance.patch('/bookings/${widget.bookingId}/review', body);
      } else {
        await ApiClient.instance.post('/bookings/${widget.bookingId}/review', body);
      }
      if (mounted) setState(() => _submitted = true);
    } on ApiException catch (e) {
      if (mounted) showCharakToast(context, message: e.message, isError: true);
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
  Widget build(BuildContext context) => CharakScreen(
        body: _submitted ? _success() : _form(),
      );

  Widget _success() => Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 34, 20, 24),
            child: Column(children: [
              CharakOutcomeState(
                title: _editing ? 'Review updated' : 'Thanks for your review',
                message: 'It helps other patients choose. You can change it for 48 hours.',
              ),
              const SizedBox(height: 20),
              CharakStarRating(value: _stars, size: 22, gap: 6),
            ]),
          ),
        ),
        CharakCtaBar.single(CharakButton(label: 'Done', onPressed: _toHistory)),
      ]);

  Widget _form() {
    final readOnly = !widget.editable;
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
          children: [
            Text(readOnly ? 'Your review' : 'How was your visit?',
                style: charakScreenTitleStyle, textAlign: TextAlign.center),
            const SizedBox(height: 5),
            Text(
              readOnly
                  ? 'Reviews can be changed for 48 hours after they\'re posted.'
                  : 'Only the stars are required. The rest is optional.',
              style: charakScreenSubStyle,
              textAlign: TextAlign.center,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 26, bottom: 8),
              child: CharakStarRating(
                value: _stars,
                onChanged: readOnly ? null : (v) => setState(() => _stars = v),
              ),
            ),
            Text(_starLabels[_stars],
                textAlign: TextAlign.center,
                style: CharakText.caption.copyWith(fontSize: 13.5, color: CharakColors.inkMuted)),
            const SizedBox(height: 22),
            if (!readOnly || _dims.values.any((v) => v > 0)) ...[
              const CharakSectionTitle(label: 'A little more (optional)'),
              const SizedBox(height: 4),
              for (final e in charakReviewDimensions.entries)
                if (!readOnly)
                  CharakDimensionPicker(
                    label: e.value,
                    value: _dims[e.key]!,
                    onChanged: (v) => setState(() => _dims[e.key] = v),
                  )
                else if (_dims[e.key]! > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(child: Text(e.value, style: CharakText.body.copyWith(color: CharakColors.ink))),
                      CharakStarRating(value: _dims[e.key]!, size: 18, gap: 3),
                    ]),
                  ),
              const SizedBox(height: 18),
            ],
            if (readOnly)
              (_commentCtrl.text.isEmpty
                  ? const SizedBox.shrink()
                  : Text(_commentCtrl.text, style: CharakText.body.copyWith(color: CharakColors.ink)))
            else
              CharakField(
                label: 'Add a comment (optional)',
                controller: _commentCtrl,
                placeholder: 'What should other patients know? Please leave out names and numbers.',
                maxLines: null,
                minLines: 4,
              ),
            const SizedBox(height: 12),
            Text(
              'Your review shows as "Verified patient". The doctor doesn\'t see who wrote it.',
              style: charakHintStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      if (readOnly)
        CharakCtaBar.single(CharakButton(label: 'Done', onPressed: _toHistory))
      else
        CharakCtaBar(children: [
          if (!_editing)
            Expanded(child: CharakButton(label: 'Skip', outlined: true, onPressed: _toHistory)),
          Expanded(
            flex: 2,
            child: CharakButton(
              label: _editing ? 'Save changes' : 'Post review',
              isLoading: _loading,
              onPressed: _stars > 0 ? _submit : null,
            ),
          ),
        ]),
    ]);
  }
}
