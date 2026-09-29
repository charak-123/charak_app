/// Living reference for CHARAK Design System V2: every core component on one
/// scrollable page, in whichever scheme is active.
///
/// Import it separately (`package:charak_core/gallery.dart`); apps don't
/// ship it. `test/gallery_golden_test.dart` renders it for both schemes into
/// `design-system/screenshots/`, so a visual change shows up in review.
library charak_gallery;

import 'package:flutter/material.dart';

import 'charak_core.dart';

class CharakGallery extends StatefulWidget {
  const CharakGallery({super.key});

  @override
  State<CharakGallery> createState() => _CharakGalleryState();
}

class _CharakGalleryState extends State<CharakGallery> {
  String _channel = 'online';
  String _slot = '10:00';
  bool _online = true;
  bool _home = false;

  @override
  Widget build(BuildContext context) {
    final doctor = CharakColors.isInk;
    return Scaffold(
      backgroundColor: CharakColors.ground,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
        children: [
          CharakScreenHeader(
            eyebrow: doctor ? 'Dr. Meera Kulkarni' : 'Wednesday, 30 September',
            title: doctor ? 'Requests' : 'Good evening,\nAarav',
            display: !doctor,
            subtitle: doctor ? '3 waiting for your decision' : 'Riya\'s consult starts soon.',
            subtitleColor: doctor ? CharakColors.greeting : null,
          ),
          const SizedBox(height: 20),
          const CharakSearchBar(onVoice: _noop, onTap: _noop),
          const SizedBox(height: 16),
          CharakCard(
            tone: CharakCardTone.hero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TOMORROW · ACCEPTED', style: CharakText.overline.copyWith(color: CharakPalette.blue100)),
              const SizedBox(height: 14),
              Row(children: [
                const CharakAvatar(name: 'Sameer Deshpande', radius: 28, tone: 1),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('Dr. Sameer Deshpande',
                      style: CharakText.titleSmall.copyWith(color: Colors.white)),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: Text('11:00 AM',
                      style: CharakText.numeric.copyWith(fontSize: 28, color: Colors.white)),
                ),
                const CharakButton(
                  label: 'Pay ₹800',
                  expand: false,
                  variant: CharakButtonVariant.inverse,
                  onPressed: _noop,
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 24),
          const CharakSectionHeader(title: 'Find care', actionLabel: 'See all', onAction: _noop),
          const SizedBox(height: 12),
          const Row(children: [
            Expanded(child: CharakSpecialtyTile(label: 'General', icon: Icons.medical_services_outlined, toneIndex: 0)),
            SizedBox(width: 10),
            Expanded(child: CharakSpecialtyTile(label: 'Paediatrics', icon: Icons.sentiment_satisfied_outlined, toneIndex: 1)),
            SizedBox(width: 10),
            Expanded(child: CharakSpecialtyTile(label: 'Cardiology', icon: Icons.favorite_border_rounded, toneIndex: 2)),
          ]),
          const SizedBox(height: 24),
          const CharakSectionTitle(label: 'Buttons'),
          const SizedBox(height: 10),
          const CharakButton(label: 'Send request', onPressed: _noop),
          const SizedBox(height: 10),
          const CharakButton(label: 'Add family member', variant: CharakButtonVariant.tonal, onPressed: _noop),
          const SizedBox(height: 10),
          const CharakButton(label: 'Reschedule', variant: CharakButtonVariant.outline, onPressed: _noop),
          const SizedBox(height: 10),
          const Row(children: [
            Expanded(child: CharakButton(label: 'Decline', variant: CharakButtonVariant.danger, onPressed: _noop)),
            SizedBox(width: 10),
            Expanded(child: CharakButton(label: 'Accept', variant: CharakButtonVariant.ink, onPressed: _noop)),
          ]),
          const SizedBox(height: 10),
          const CharakButton(label: 'Pick a slot to continue'),
          const SizedBox(height: 24),
          const CharakSectionTitle(label: 'Chips, segments & status'),
          const SizedBox(height: 10),
          CharakSegmented<String>(
            value: _channel,
            onChanged: (v) => setState(() => _channel = v),
            segments: const [
              CharakSegment(value: 'online', label: 'Online'),
              CharakSegment(value: 'home', label: 'Home visit'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in ['9:30', '10:00', '10:30'])
              CharakChip(label: t, numeric: true, selected: _slot == t, onTap: () => setState(() => _slot = t)),
            const CharakChip(label: '11:00', numeric: true, disabled: true),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in ['requested', 'accepted', 'paid', 'in_progress', 'review', 'declined'])
              CharakStatusPill.forStatus(s),
          ]),
          const SizedBox(height: 24),
          CharakGroupedList(
            label: 'Consultation',
            children: [
              CharakListRow(
                title: 'Online consults',
                subtitle: _online ? 'On · ₹500 per call' : 'Off',
                showChevron: false,
                trailing: CharakSwitch(value: _online, onChanged: (v) => setState(() => _online = v)),
              ),
              CharakListRow(
                title: 'Home visits',
                subtitle: _home ? 'On' : 'Off',
                showChevron: false,
                trailing: CharakSwitch(value: _home, onChanged: (v) => setState(() => _home = v)),
              ),
              const CharakListRow(title: 'Procedures & pricing', subtitle: '12 procedures', last: true, onTap: _noop),
            ],
          ),
          const SizedBox(height: 24),
          CharakCard(
            child: Column(children: [
              const Row(children: [
                CharakAvatar(name: 'Meera Kulkarni', radius: 26, tone: 2),
                SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Dr. Meera Kulkarni', style: CharakText.titleSmall),
                    Text('Paediatrics · 11 yrs', style: CharakText.caption),
                  ]),
                ),
                CharakRatingChip(rating: '4.8'),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Text('Next: Today 5:30 PM', style: CharakText.label.tabular.copyWith(color: CharakColors.inkMuted)),
                const Spacer(),
                Text('₹650', style: CharakText.numeric.copyWith(color: CharakColors.ink)),
              ]),
            ]),
          ),
          const SizedBox(height: 24),
          const CharakField(label: "What's bothering you?", placeholder: 'Fever since 2 days, mild cough'),
          const SizedBox(height: 24),
          const CharakInfoStrip(label: 'Consult starts in', value: '11:53', tabularValue: true, icon: Icons.videocam_outlined),
          const SizedBox(height: 10),
          const CharakNoteBanner(
            icon: Icons.shield_outlined,
            tone: CharakStatusTone.review,
            leadLabel: 'Under senior review.',
            message: 'You can pay once a senior doctor approves the bill.',
          ),
          const SizedBox(height: 24),
          const CharakNowBar(
            icon: Icons.videocam_outlined,
            title: 'Dr. Meera · Riya\'s consult',
            subtitle: 'Online · Paediatrics',
            trailing: 'in 11:53',
            delay: Duration.zero,
          ),
          const SizedBox(height: 24),
          const Center(child: CharakWordmark()),
        ],
      ),
      bottomNavigationBar: CharakBottomBar(
        currentIndex: 0,
        onTap: (_) {},
        items: doctor
            ? const [
                CharakNavItem(label: 'Requests', icon: Icons.inbox_outlined, activeIcon: Icons.inbox_rounded, badge: 3),
                CharakNavItem(label: 'Schedule', icon: Icons.calendar_month_outlined),
                CharakNavItem(label: 'Earnings', icon: Icons.account_balance_wallet_outlined),
                CharakNavItem(label: 'Profile', icon: Icons.person_outline_rounded),
              ]
            : const [
                CharakNavItem(label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home_rounded),
                CharakNavItem(label: 'Bookings', icon: Icons.calendar_month_outlined),
                CharakNavItem(label: 'History', icon: Icons.history_rounded),
                CharakNavItem(label: 'Profile', icon: Icons.person_outline_rounded),
              ],
      ),
    );
  }
}

void _noop() {}
