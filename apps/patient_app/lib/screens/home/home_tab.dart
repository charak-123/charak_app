import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

import '../notifications/notifications_screen.dart';
import 'booking_providers.dart';

/// (directory filter, tile label, icon, tile tone index into CharakTileTones.all).
/// Tile labels are the short names from the design system so they fit one
/// line on a third-width tile; the filter keeps the full specialty name.
const _specialties = [
  ('General Physician', 'General', LucideIcons.stethoscope, 0),
  ('Pediatrics', 'Paediatrics', LucideIcons.baby, 1),
  ('Cardiology', 'Cardiology', LucideIcons.heartPulse, 2),
  ('Dermatology', 'Skin', LucideIcons.scanFace, 4),
  ('Orthopedic', 'Ortho', LucideIcons.bone, 5),
  ('Physiotherapy', 'Physio', LucideIcons.personStanding, 3),
  ('Gynecology', 'Gynae', LucideIcons.venus, 2),
  ('Nurse', 'Nurse', LucideIcons.syringe, 0),
];

/// Patient Home (design-system/README.md § Screens · Patient Home).
///
/// Top third: date (Chandan), a big display greeting and one line of status.
/// Lower two-thirds: search, the next booking as a blue hero card with its
/// action (Pay / View), then Find care tiles. A Now Bar floats above the tab
/// bar when a paid online consult starts within the hour.
class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final name = (user?['name'] as String?) ?? '';
    final firstName = name.isEmpty ? 'there' : name.split(' ').first;
    final bookings = ref.watch(patientBookingsProvider).valueOrNull ?? const [];

    final upcoming = _upcoming(bookings);
    final next = upcoming.isEmpty ? null : upcoming.first;
    final live = upcoming.where(_isLiveSoon).firstOrNull;

    final status = next == null
        ? 'Book a home visit or an online consult in a few taps.'
        : live != null
            ? 'Your consult starts soon. Everything else is on track.'
            : 'You have ${upcoming.length} upcoming booking${upcoming.length == 1 ? '' : 's'}.';

    final unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;
    final ready = bookings.where((b) => b['status'] == 'consulted').toList();
    final followUps = ref.watch(followUpsProvider).valueOrNull ?? const [];
    return CharakLargeTitleScaffold(
      eyebrow: DateFormat('EEEE, d MMMM').format(DateTime.now()),
      title: '${_greeting()},\n$firstName',
      barTitle: 'Home',
      display: true,
      subtitle: status,
      actions: [
        Stack(clipBehavior: Clip.none, children: [
          CharakRoundIconButton(
            icon: LucideIcons.bell,
            semanticLabel: unread > 0 ? 'Notifications, $unread new' : 'Notifications',
            filled: false,
            onTap: () => context.push('/notifications'),
          ),
          if (unread > 0)
            Positioned(
              top: 10,
              right: 11,
              child: IgnorePointer(
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: CharakColors.chandan,
                    shape: BoxShape.circle,
                    border: Border.all(color: CharakColors.ground, width: 2),
                  ),
                ),
              ),
            ),
        ]),
        GestureDetector(
          onTap: () => ref.read(homeTabIndexProvider.notifier).state = 3,
          child: CharakAvatar(name: name.isEmpty ? '?' : name, radius: 22, circle: true, tone: 6),
        ),
      ],
      onRefresh: () {
        ref.invalidate(followUpsProvider);
        return ref.refresh(patientBookingsProvider.future);
      },
      floating: live == null ? null : _ConsultNowBar(booking: live),
      children: [
        CharakSearchBar(
          onTap: () => context.push('/directory'),
          onVoice: () => context.push('/directory'),
        ),
        if (next != null) ...[
          const SizedBox(height: 16),
          _NextBookingHero(booking: next),
        ],
        if (ready.isNotEmpty || followUps.isNotEmpty) ...[
          const SizedBox(height: 24),
          CharakGroupedList(label: 'For you', children: [
            for (final (i, b) in ready.indexed)
              CharakListRow(
                icon: LucideIcons.fileText,
                title: 'Your prescription is ready',
                subtitle: '${CharakFormat.doctor((b['doctors'] as Map?)?['name'] as String?)} · '
                    'open it to complete your visit',
                last: i == ready.length - 1 && followUps.isEmpty,
                onTap: () => context.push('/booking/${b['id']}/active'),
              ),
            for (final (i, f) in followUps.indexed)
              CharakListRow(
                icon: LucideIcons.calendarClock,
                title: 'Follow-up with ${CharakFormat.doctor((f['doctors'] as Map?)?['name'] as String?)}',
                subtitle: _followUpLine(f),
                last: i == followUps.length - 1,
                onTap: () => _followUpSheet(context, ref, f),
              ),
          ]),
        ],
        const SizedBox(height: 28),
        CharakSectionHeader(
          title: 'Find care',
          actionLabel: 'See all',
          onAction: () => context.push('/directory'),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 88,
          ),
          itemCount: _specialties.length,
          itemBuilder: (_, i) {
            final (filter, label, icon, tone) = _specialties[i];
            return CharakSpecialtyTile(
              label: label,
              icon: icon,
              toneIndex: tone,
              onTap: () => context.push('/directory?q=${Uri.encodeQueryComponent(filter)}'),
            );
          },
        ),
      ],
    );
  }

  static String _followUpLine(Map<String, dynamic> f) {
    final when = DateTime.tryParse(f['recommended_date'] as String? ?? '');
    final channel = CharakFollowUp.fromJson(f).channelLabel;
    if (when == null) return channel;
    final today = DateTime.now();
    final past = when.isBefore(DateTime(today.year, today.month, today.day));
    return '${past ? 'Was due' : 'Around'} ${DateFormat('EEE d MMM').format(when)} · $channel';
  }

  /// The recommendation, with Book (the doctor's profile, to pick a slot) and
  /// Dismiss. Nothing was booked for the patient, and the sheet says so.
  Future<void> _followUpSheet(BuildContext context, WidgetRef ref, Map<String, dynamic> f) async {
    final followUp = CharakFollowUp.fromJson(f);
    final action = await showCharakSheet<String>(
      context,
      title: 'Follow-up recommended',
      child: Builder(
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CharakFollowUpLine(followUp: followUp),
          const SizedBox(height: 12),
          Text('Your doctor recommended this. Nothing has been booked: pick a slot if you need it.',
              style: charakHintStyle),
          const SizedBox(height: 16),
          CharakButton(label: 'Book follow-up', onPressed: () => Navigator.pop(ctx, 'book')),
          const SizedBox(height: 8),
          CharakButton(label: 'Dismiss', variant: CharakButtonVariant.outline,
              onPressed: () => Navigator.pop(ctx, 'dismiss')),
        ]),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'book') {
      // At the follow-up price, if this consultation still qualifies.
      context.push('/book/${f['doctor_id']}/channel', extra: {'follow_up_of': f['booking_id']});
      return;
    }
    try {
      await ApiClient.instance.post('/me/follow-ups/${f['id']}/dismiss', {});
      ref.invalidate(followUpsProvider);
    } on ApiException catch (e) {
      if (context.mounted) showCharakToast(context, message: e.message, isError: true);
    }
  }

  static DateTime? _start(Map<String, dynamic> b) {
    final s = b['scheduled_start'] as String?;
    return s == null ? null : DateTime.tryParse(s)?.toLocal();
  }

  /// Requested / accepted / paid bookings that haven't started, soonest first.
  static List<Map<String, dynamic>> _upcoming(List<Map<String, dynamic>> all) {
    final now = DateTime.now().subtract(const Duration(minutes: 30));
    final list = all.where((b) {
      final st = b['status'];
      final at = _start(b);
      return (st == 'requested' || st == 'accepted' || st == 'paid' || st == 'in_progress') &&
          at != null && at.isAfter(now);
    }).toList()
      ..sort((a, b) => _start(a)!.compareTo(_start(b)!));
    return list;
  }

  static bool _isLiveSoon(Map<String, dynamic> b) {
    final at = _start(b);
    if (at == null || b['status'] != 'paid' || b['channel'] == 'home_visit') return false;
    final diff = at.difference(DateTime.now());
    return diff.inMinutes <= 60 && diff.inMinutes > -30;
  }
}

/// The next booking as a blue hero card: overline (day · status), channel
/// chip, doctor, then the time in narrow tabular figures and its action.
class _NextBookingHero extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _NextBookingHero({required this.booking});

  @override
  Widget build(BuildContext context) {
    final id = booking['id'] as String;
    final status = booking['status'] as String? ?? 'requested';
    final channel = booking['channel'] as String? ?? '';
    final doc = booking['doctors'] as Map? ?? const {};
    final docName = CharakFormat.doctor(doc['name'] as String?);
    final category = (doc['categories'] as Map?)?['name'] as String? ?? '';
    final pricing = List<Map<String, dynamic>>.from(doc['doctor_pricing'] as List? ?? const []);
    final price = pricing.where((p) => p['channel'] == channel).firstOrNull?['price'] as num?;
    final at = DateTime.tryParse(booking['scheduled_start'] as String? ?? '')?.toLocal();

    final day = at == null ? '' : _dayLabel(at);
    final (_, statusLabel) = charakStatusFor(status);
    final white = CharakText.body.copyWith(color: CharakColors.onPrimary);

    final (actionLabel, route) = switch (status) {
      'accepted' => (price != null ? 'Pay ${CharakFormat.rupees(price)}' : 'Pay', '/booking/$id/pay'),
      'paid' || 'in_progress' => ('View', '/booking/$id/active'),
      _ => ('Status', '/booking/$id/status'),
    };

    return CharakCard(
      tone: CharakCardTone.hero,
      onTap: () => context.push(route),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${day.toUpperCase()} · ${statusLabel.toUpperCase()}',
                style: CharakText.overline.copyWith(color: CharakPalette.blue100)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: CharakColors.onPrimary.withValues(alpha: 0.18),
              borderRadius: const BorderRadius.all(CharakRadius.pill),
            ),
            child: Text(channel == 'home_visit' ? 'Home visit' : 'Online',
                style: CharakText.caption.weight(600).copyWith(color: CharakColors.onPrimary)),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          CharakAvatar(name: docName, radius: 28, tone: 1),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(CharakFormat.doctor(docName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CharakText.titleSmall.copyWith(color: CharakColors.onPrimary)),
              if (category.isNotEmpty)
                Text(category, style: white.copyWith(fontSize: 14, color: CharakPalette.blue100)),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (at != null) ...[
                Text(DateFormat('h:mm a').format(at),
                    style: CharakText.numeric.copyWith(fontSize: 28, height: 1.1, color: CharakColors.onPrimary)),
                Text(DateFormat('EEE, d MMM').format(at),
                    style: CharakText.caption.copyWith(color: CharakPalette.blue100)),
              ],
            ]),
          ),
          CharakButton(
            label: actionLabel,
            expand: false,
            variant: CharakButtonVariant.inverse,
            onPressed: () => context.push(route),
          ),
        ]),
      ]),
    );
  }

  static String _dayLabel(DateTime at) {
    final today = DateUtils.dateOnly(DateTime.now());
    final d = DateUtils.dateOnly(at).difference(today).inDays;
    if (d == 0) return 'Today';
    if (d == 1) return 'Tomorrow';
    return DateFormat('EEEE').format(at);
  }
}

/// Now Bar for a paid online consult starting within the hour. The
/// countdown ticks every second in tabular figures.
class _ConsultNowBar extends StatefulWidget {
  final Map<String, dynamic> booking;
  const _ConsultNowBar({required this.booking});

  @override
  State<_ConsultNowBar> createState() => _ConsultNowBarState();
}

class _ConsultNowBarState extends State<_ConsultNowBar> {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted) setState(() {});
  });

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final doc = b['doctors'] as Map? ?? const {};
    final at = DateTime.tryParse(b['scheduled_start'] as String? ?? '')?.toLocal() ?? DateTime.now();
    final left = at.difference(DateTime.now());
    final countdown = left.isNegative
        ? 'Now'
        : 'in ${left.inMinutes.toString().padLeft(2, '0')}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    final category = (doc['categories'] as Map?)?['name'] as String?;
    return CharakNowBar(
      icon: LucideIcons.video,
      title: '${CharakFormat.doctor(doc['name'] as String?)} · your consult',
      subtitle: ['Online', if (category != null) category].join(' · '),
      trailing: countdown,
      actionLabel: 'Join waiting room',
      onAction: () => context.push('/booking/${b['id']}/active'),
    );
  }
}
