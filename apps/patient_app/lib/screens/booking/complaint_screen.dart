import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../home/booking_providers.dart';

/// Submit a complaint against a booking. If [bookingId] is given (e.g. from
/// a history-detail screen) the booking is fixed; otherwise (e.g. from the
/// Profile menu) the patient picks from their recent completed visits.
class ComplaintScreen extends ConsumerStatefulWidget {
  final String? bookingId;
  const ComplaintScreen({super.key, this.bookingId});
  @override
  ConsumerState<ComplaintScreen> createState() => _State();
}

class _State extends ConsumerState<ComplaintScreen> {
  final _descCtrl = TextEditingController();
  bool _sending = false;
  String? _refId;
  String? _selectedBookingId;

  @override
  void initState() {
    super.initState();
    _selectedBookingId = widget.bookingId;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final bookingId = _selectedBookingId;
    if (bookingId == null) return;
    setState(() => _sending = true);
    try {
      final res = await ApiClient.instance.post(
        '/bookings/$bookingId/complaint',
        {'description': _descCtrl.text.trim()},
      ) as Map<String, dynamic>;
      if (mounted) setState(() => _refId = res['id'] as String?);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: CharakColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CharakColors.bg,
    appBar: const CharakTopBar(title: 'Submit a complaint'),
    body: _refId != null
        ? _SuccessBody(refId: _refId!)
        : widget.bookingId != null
            ? _FormBody(
                descCtrl: _descCtrl,
                sending: _sending,
                canSubmit: _descCtrl.text.trim().isNotEmpty,
                onSubmit: _submit,
              )
            : _PickerForm(
                descCtrl: _descCtrl,
                sending: _sending,
                selectedId: _selectedBookingId,
                onSelect: (id) => setState(() => _selectedBookingId = id),
                onSubmit: _submit,
              ),
  );
}

class _PickerForm extends ConsumerWidget {
  final TextEditingController descCtrl;
  final bool sending;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onSubmit;
  const _PickerForm({
    required this.descCtrl,
    required this.sending,
    required this.selectedId,
    required this.onSelect,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientBookingsProvider);
    return async.when(
      loading: () => const _ComplaintLoading(),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (bookings) {
        final eligible = bookings
            .where((b) => b['status'] == 'completed')
            .take(3)
            .toList();
        if (selectedId == null && eligible.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onSelect(eligible.first['id'] as String));
        }
        return _FormBody(
          descCtrl: descCtrl,
          sending: sending,
          canSubmit: selectedId != null && descCtrl.text.trim().isNotEmpty,
          onSubmit: onSubmit,
          picker: eligible.isEmpty
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Text('No completed visits yet to file a complaint against.',
                      style: charakScreenSubStyle),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const CharakSectionTitle(label: 'Which booking?'),
                  const SizedBox(height: 10),
                  // `.comp-picker` — wrapping pill picker, one booking each.
                  Wrap(spacing: 8, runSpacing: 8, children: eligible.map((b) {
                    final id = b['id'] as String;
                    final docName = (b['doctors'] as Map?)?['name'] as String? ?? 'Doctor';
                    return _CompPick(
                      label: docName,
                      selected: id == selectedId,
                      onTap: () => onSelect(id),
                    );
                  }).toList()),
                  const SizedBox(height: 18),
                ]),
        );
      },
    );
  }
}

/// `.comp-pick` — 9/14 pill, muted until picked, then solid `ink`.
class _CompPick extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CompPick({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: CharakDurations.buttonPress,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? CharakColors.ink : CharakColors.bgSubtle,
        borderRadius: const BorderRadius.all(CharakRadius.pill),
      ),
      child: Text(label,
          style: CharakText.caption.copyWith(
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : CharakColors.inkMuted,
          )),
    ),
  );
}

class _FormBody extends StatelessWidget {
  final TextEditingController descCtrl;
  final bool sending;
  final bool canSubmit;
  final VoidCallback onSubmit;
  final Widget? picker;
  const _FormBody({
    required this.descCtrl,
    required this.sending,
    required this.canSubmit,
    required this.onSubmit,
    this.picker,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
    Expanded(child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const Text('Tied to a booking — handled by our team, not the doctor.',
            style: charakScreenSubStyle),
        const SizedBox(height: 14),
        if (picker != null) picker!,
        CharakField(
          label: 'Describe the issue',
          controller: descCtrl,
          placeholder: 'What went wrong? Be specific — dates, times, anything '
              'the team should know.',
          maxLines: null,
          minLines: 5,
        ),
        // `.exp-line`
        const SizedBox(height: 14),
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.verified_user_outlined,
                size: 15, color: CharakColors.primary),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'A member of our team will review this within 1–2 working days '
              'and get back to you here.',
              style: charakHintStyle,
            ),
          ),
        ]),
      ],
    )),
    CharakCtaBar.single(
      ValueListenableBuilder(
        valueListenable: descCtrl,
        builder: (_, __, ___) => CharakButton(
          label: 'Submit complaint',
          isLoading: sending,
          onPressed: canSubmit ? onSubmit : null,
        ),
      ),
    ),
  ]);
}

class _SuccessBody extends ConsumerWidget {
  final String refId;
  const _SuccessBody({required this.refId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortRef =
        refId.substring(0, refId.length < 8 ? refId.length : 8).toUpperCase();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 34, 20, 24),
      child: CharakOutcomeState(
        title: 'Complaint received',
        message: "We'll review it within 1–2 working days and reply here.",
        child: Column(children: [
          // `.ref-no` — monospaced reference chip.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: CharakColors.bgSubtle,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Ref CMP-$shortRef',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.4,
                  color: CharakColors.ink,
                )),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: CharakButton(
              label: 'Back to profile',
              outlined: true,
              onPressed: () {
                ref.read(homeTabIndexProvider.notifier).state = 3;
                context.go('/home');
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Loading state: `.skel` blocks for the intro line, the `.comp-picker` pills
/// and the description field.
class _ComplaintLoading extends StatelessWidget {
  const _ComplaintLoading();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CharakSkeleton(height: 14),
        SizedBox(height: 20),
        CharakSkeleton(width: 120, height: 13),
        SizedBox(height: 10),
        Row(children: [
          CharakSkeleton(width: 96, height: 34, radius: 17),
          SizedBox(width: 8),
          CharakSkeleton(width: 82, height: 34, radius: 17),
          SizedBox(width: 8),
          CharakSkeleton(width: 74, height: 34, radius: 17),
        ]),
        SizedBox(height: 22),
        CharakSkeleton(width: 140, height: 13),
        SizedBox(height: 10),
        CharakSkeleton(height: 118, radius: 12),
      ],
    ),
  );
}
