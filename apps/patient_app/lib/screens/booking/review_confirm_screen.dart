import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';
import '../shared/charak_button.dart';

class ReviewConfirmScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> booking;
  const ReviewConfirmScreen({super.key, required this.booking});
  @override
  ConsumerState<ReviewConfirmScreen> createState() => _State();
}

class _State extends ConsumerState<ReviewConfirmScreen> {
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final b = widget.booking;

      // 1. Create booking
      final created = await ApiClient.instance.post('/bookings/', {
        'doctor_id':       b['doctor_id'] as String,
        'channel':         b['channel'] as String,
        'scheduled_start': b['scheduled_start'] as String,
      }) as Map<String, dynamic>;

      final bookingId = created['id'] as String;

      // 2. Upload intake items
      final text = b['text'] as String? ?? '';
      if (text.isNotEmpty) {
        await ApiClient.instance.post('/bookings/$bookingId/intake', {
          'media_type': 'text',
          'transcript_text': text,
        });
      }

      final transcript = b['voice_transcript'] as String?;
      if (transcript != null && transcript.isNotEmpty) {
        await ApiClient.instance.post('/bookings/$bookingId/intake', {
          'media_type': 'voice',
          'transcript_text': transcript,
        });
      }

      // Image uploads happen in background (file upload to Supabase storage
      // is handled separately — skipped here, URL posted once uploaded)

      if (mounted) context.go('/book/sent/$bookingId');
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
  Widget build(BuildContext context) {
    final b       = widget.booking;
    final channel = b['channel'] as String? ?? '';
    final start   = b['scheduled_start'] as String? ?? '';
    final dt      = DateTime.tryParse(start.replaceAll('+05:30',''))?.toLocal();
    final dateStr = dt != null ? DateFormat('EEEE, d MMM · h:mm a').format(dt) : start;
    final text    = b['text'] as String? ?? '';
    final images  = b['images'] as List? ?? [];

    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('Review & Confirm'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
      ),
      body: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(CharakSpacing.base), children: [
          _SummaryCard(channel: channel, dateStr: dateStr),
          const SizedBox(height: 12),
          if (text.isNotEmpty) _IntakeCard(text: text),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ImagesCard(count: images.length),
          ],
          const SizedBox(height: 12),
          _DisclaimerCard(),
        ])),

        Container(
          padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 12, CharakSpacing.base, 24),
          color: CharakColors.bg,
          child: CharakButton(
            label: 'Send Request',
            isLoading: _sending,
            onPressed: _send,
          ),
        ),
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String channel;
  final String dateStr;
  const _SummaryCard({required this.channel, required this.dateStr});
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(CharakRadius.card),
      side: const BorderSide(color: CharakColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(CharakSpacing.base),
      child: Column(children: [
        Row(children: [
          Icon(
            channel == 'home_visit' ? Icons.home_outlined : Icons.videocam_outlined,
            color: channel == 'home_visit' ? CharakColors.success : CharakColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(channel == 'home_visit' ? 'Home Visit' : 'Online Consult',
              style: CharakText.bodyMed),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.schedule, color: CharakColors.inkMuted, size: 16),
          const SizedBox(width: 8),
          Text(dateStr, style: CharakText.body),
        ]),
      ]),
    ),
  );
}

class _IntakeCard extends StatelessWidget {
  final String text;
  const _IntakeCard({required this.text});
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
        Text('Your description', style: CharakText.h2),
        const SizedBox(height: 8),
        Text(text, style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
      ]),
    ),
  );
}

class _ImagesCard extends StatelessWidget {
  final int count;
  const _ImagesCard({required this.count});
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(CharakRadius.card),
      side: const BorderSide(color: CharakColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(CharakSpacing.base),
      child: Row(children: [
        const Icon(Icons.image_outlined, color: CharakColors.inkMuted),
        const SizedBox(width: 8),
        Text('$count photo${count > 1 ? 's' : ''} attached', style: CharakText.body),
      ]),
    ),
  );
}

class _DisclaimerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: CharakColors.bgSubtle,
      borderRadius: BorderRadius.all(CharakRadius.card),
      border: Border.all(color: CharakColors.border),
    ),
    child: Text(
      'By sending this request you consent to sharing the above information with the doctor. '
      'Charak is a platform connecting patients with healthcare providers. '
      'We do not provide medical advice.',
      style: CharakText.micro.copyWith(color: CharakColors.inkMuted),
    ),
  );
}
