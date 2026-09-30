import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

import 'booking_providers.dart';

/// (label, icon, tile tone index into CharakTileTones.all)
const _specialties = [
  ('General Physician', Icons.medical_services_outlined, 0),
  ('Pediatrics', Icons.sentiment_satisfied_outlined, 1),
  ('Cardiology', Icons.favorite_border_rounded, 2),
  ('Physiotherapy', Icons.spa_outlined, 3),
  ('Dermatology', Icons.water_drop_outlined, 4),
  ('Orthopedic', Icons.accessibility_new_outlined, 5),
  ('Gynecology', Icons.child_friendly_outlined, 1),
  ('Nurse', Icons.vaccines_outlined, 0),
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

    return CharakLargeTitleScaffold(
      eyebrow: DateFormat('EEEE, d MMMM').format(DateTime.now()),
      title: '${_greeting()},\n$firstName',
      barTitle: 'Home',
      display: true,
      subtitle: status,
      actions: [
        CharakRoundIconButton(
          icon: Icons.notifications_none_rounded,
          semanticLabel: 'Notifications',
          filled: false,
          onTap: () {},
        ),
        GestureDetector(
          onTap: () => ref.read(homeTabIndexProvider.notifier).state = 3,
          child: CharakAvatar(name: name.isEmpty ? '?' : name, radius: 22, circle: true, tone: 6),
        ),
      ],
      onRefresh: () => ref.refresh(patientBookingsProvider.future),
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
            mainAxisExtent: 96,
          ),
          itemCount: _specialties.length,
          itemBuilder: (_, i) {
            final (label, icon, tone) = _specialties[i];
            return CharakSpecialtyTile(
              label: label == 'General Physician' ? 'General' : label,
              icon: icon,
              toneIndex: tone,
              onTap: () => context.push('/directory', extra: label),
            );
          },
        ),
      ],
    );
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
      return (st == 'requested' || st == 'accepted' || st == 'paid') && at != null && at.isAfter(now);
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
    final docName = doc['name'] as String? ?? 'Doctor';
    final category = (doc['categories'] as Map?)?['name'] as String? ?? '';
    final pricing = List<Map<String, dynamic>>.from(doc['doctor_pricing'] as List? ?? const []);
    final price = pricing.where((p) => p['channel'] == channel).firstOrNull?['price'] as num?;
    final at = DateTime.tryParse(booking['scheduled_start'] as String? ?? '')?.toLocal();

    final day = at == null ? '' : _dayLabel(at);
    final (_, statusLabel) = charakStatusFor(status);
    final white = CharakText.body.copyWith(color: CharakColors.onPrimary);

    final (actionLabel, route) = switch (status) {
      'accepted' => (price != null ? 'Pay ₹${price.toStringAsFixed(0)}' : 'Pay', '/booking/$id/pay'),
      'paid' => ('View', '/booking/$id/active'),
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
              Text('Dr. $docName',
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
      icon: Icons.videocam_outlined,
      title: 'Dr. ${doc['name'] ?? 'Doctor'} · your consult',
      subtitle: ['Online', if (category != null) category].join(' · '),
      trailing: countdown,
      actionLabel: 'Join waiting room',
      onAction: () => context.push('/booking/${b['id']}/active'),
    );
  }
}
