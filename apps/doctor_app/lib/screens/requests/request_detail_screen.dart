import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';
import '../shared/charak_button.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _bookingDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final booking = await ApiClient.instance.get('/bookings/$id');
  final intake  = await ApiClient.instance.get('/bookings/$id/intake');
  return {
    'booking': booking as Map<String, dynamic>,
    'intake': intake as List,
  };
});

// ── Screen ────────────────────────────────────────────────────────────────────

class RequestDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const RequestDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends ConsumerState<RequestDetailScreen> {
  bool _deciding = false;

  Future<void> _accept() async {
    setState(() => _deciding = true);
    try {
      await ApiClient.instance.patch('/bookings/${widget.bookingId}/accept', {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking accepted'), backgroundColor: CharakColors.success),
        );
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  Future<void> _decline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline request?'),
        content: const Text('The patient will be notified that you\'re unavailable for this slot.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline', style: TextStyle(color: CharakColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deciding = true);
    try {
      await ApiClient.instance.patch('/bookings/${widget.bookingId}/decline', {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking declined')),
        );
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: CharakColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_bookingDetailProvider(widget.bookingId));
    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('Request Details'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final booking = data['booking'] as Map<String, dynamic>;
          final intake  = List<Map<String, dynamic>>.from(data['intake'] as List);
          return Column(children: [
            Expanded(child: ListView(padding: const EdgeInsets.all(CharakSpacing.base), children: [
              _PatientCard(booking: booking),
              const SizedBox(height: 12),
              _VisitCard(booking: booking),
              if (intake.isNotEmpty) ...[
                const SizedBox(height: 12),
                _IntakeSection(items: intake),
              ],
            ])),
            if (booking['status'] == 'requested')
              _DecisionBar(deciding: _deciding, onAccept: _accept, onDecline: _decline),
          ]);
        },
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _PatientCard({required this.booking});
  @override
  Widget build(BuildContext context) {
    final patient = booking['users'] as Map<String, dynamic>? ?? {};
    final name    = patient['name'] as String? ?? 'Unknown patient';
    final phone   = patient['phone'] as String? ?? '';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(CharakRadius.card),
        side: const BorderSide(color: CharakColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CharakSpacing.base),
        child: Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: CharakColors.primarySoft,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: CharakText.h2.copyWith(color: CharakColors.primary)),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: CharakText.bodyMed),
            if (phone.isNotEmpty)
              Text(phone, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
          ]),
        ]),
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _VisitCard({required this.booking});
  @override
  Widget build(BuildContext context) {
    final channel = booking['channel'] as String? ?? '';
    final start   = booking['scheduled_start'] as String? ?? '';
    final dt      = start.isNotEmpty ? DateTime.tryParse(start)?.toLocal() : null;
    final dateStr = dt != null ? DateFormat('EEEE, d MMMM yyyy').format(dt) : '—';
    final timeStr = dt != null ? DateFormat('h:mm a').format(dt) : '';
    final price   = booking['price_confirmed'];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(CharakRadius.card),
        side: const BorderSide(color: CharakColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CharakSpacing.base),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Visit Details', style: CharakText.h2),
          const SizedBox(height: 12),
          _Row(icon: Icons.category_outlined,
              label: channel == 'home_visit' ? 'Home Visit' : 'Online Consult'),
          const SizedBox(height: 8),
          _Row(icon: Icons.calendar_today_outlined, label: dateStr),
          const SizedBox(height: 8),
          _Row(icon: Icons.access_time, label: timeStr),
          if (price != null) ...[
            const SizedBox(height: 8),
            _Row(icon: Icons.currency_rupee, label: '₹${price.toStringAsFixed(0)}'),
          ],
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Row({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: CharakColors.inkMuted),
    const SizedBox(width: 8),
    Expanded(child: Text(label, style: CharakText.body)),
  ]);
}

class _IntakeSection extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _IntakeSection({required this.items});
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(CharakRadius.card),
      side: const BorderSide(color: CharakColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(CharakSpacing.base),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Patient Intake', style: CharakText.h2),
        const SizedBox(height: 12),
        ...items.map((item) => _IntakeItem(item: item)),
      ]),
    ),
  );
}

class _IntakeItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const _IntakeItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final type = item['media_type'] as String? ?? '';
    final text = item['transcript_text'] as String?;
    final url  = item['file_url'] as String?;

    IconData icon;
    switch (type) {
      case 'voice': icon = Icons.mic_outlined; break;
      case 'video': icon = Icons.videocam_outlined; break;
      case 'image': icon = Icons.image_outlined; break;
      default:      icon = Icons.text_snippet_outlined;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: CharakColors.primary),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (text != null && text.isNotEmpty)
            Text(text, style: CharakText.body),
          if (url != null && text == null)
            Text('[$type file]', style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
        ])),
      ]),
    );
  }
}

class _DecisionBar extends StatelessWidget {
  final bool deciding;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _DecisionBar({required this.deciding, required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 12, CharakSpacing.base, 24),
    decoration: const BoxDecoration(
      color: CharakColors.bg,
      border: Border(top: BorderSide(color: CharakColors.border)),
    ),
    child: Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: deciding ? null : onDecline,
          style: OutlinedButton.styleFrom(
            foregroundColor: CharakColors.danger,
            side: const BorderSide(color: CharakColors.danger),
            minimumSize: const Size(0, 48),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(CharakRadius.button)),
          ),
          child: const Text('Decline'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: CharakButton(
          label: 'Accept',
          isLoading: deciding,
          onPressed: onAccept,
        ),
      ),
    ]),
  );
}
