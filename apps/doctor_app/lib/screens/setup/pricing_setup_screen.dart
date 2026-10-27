import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

/// Lengths a doctor can price; matches DURATIONS in
/// backend/app/services/pricing.py.
const _kLengths = [10, 15, 20, 30, 45, 60];

/// At most this many lengths in one price list (pricing.MAX_DURATIONS_PER_LIST).
const _kMaxLengths = 4;

/// Follow-up windows offered as chips (the backend takes 1–60 days).
const _kValidityDays = [3, 5, 7, 14, 30];

/// One price list: a channel's first-visit or follow-up prices, by length.
class _PriceList {
  final String channel;
  final String category;
  final Map<int, TextEditingController> byLength = {};
  _PriceList(this.channel, this.category);

  bool get isFollowUp => category == 'follow_up';

  void toggle(int minutes) {
    final c = byLength.remove(minutes);
    if (c != null) {
      c.dispose();
    } else if (byLength.length < _kMaxLengths) {
      byLength[minutes] = TextEditingController();
    }
  }

  /// Whole rupees, or null when the box is empty or not a number.
  int? rupees(int minutes) => int.tryParse(byLength[minutes]?.text.trim() ?? '');

  bool get complete => byLength.keys.every((m) {
        final r = rupees(m);
        return r != null && r <= 50000 && (isFollowUp ? r >= 0 : r > 0);
      });

  List<Map<String, dynamic>> toRules() => [
        for (final m in (byLength.keys.toList()..sort()))
          {'channel': channel, 'visit_category': category, 'duration_min': m, 'price_paise': rupees(m)! * 100},
      ];

  void dispose() {
    for (final c in byLength.values) {
      c.dispose();
    }
  }
}

class _ProcedureEntry {
  /// Set for a procedure already saved on the server; null for a new row.
  final String? id;
  final nameCtrl  = TextEditingController();
  final priceCtrl = TextEditingController();
  _ProcedureEntry({this.id, String name = '', String price = ''}) {
    nameCtrl.text = name;
    priceCtrl.text = price;
  }
  void dispose() { nameCtrl.dispose(); priceCtrl.dispose(); }
  bool get valid => nameCtrl.text.trim().isNotEmpty && double.tryParse(priceCtrl.text) != null;
}

class PricingSetupScreen extends ConsumerStatefulWidget {
  const PricingSetupScreen({super.key});

  @override
  ConsumerState<PricingSetupScreen> createState() => _PricingSetupScreenState();
}

class _PricingSetupScreenState extends ConsumerState<PricingSetupScreen> {
  // Consult fees: first-visit and follow-up prices for each channel, by length.
  final _lists = {
    for (final ch in ['online_consult', 'home_visit'])
      for (final cat in ['initial', 'follow_up']) '$ch|$cat': _PriceList(ch, cat),
  };
  int? _validityDays;
  final _thresholdCtrl   = TextEditingController();

  _PriceList _list(String channel, String category) => _lists['$channel|$category']!;

  final List<_ProcedureEntry> _procs = [_ProcedureEntry()];
  final List<String> _removedProcIds = [];

  /// True once this doctor has saved prices before: the screen is then a
  /// settings editor pushed from the profile, not the last onboarding step.
  bool _editing = false;

  bool _loadingDoctorInfo = true;
  bool _offersOnline = false, _offersHome = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDoctorInfo();
  }

  @override
  void dispose() {
    for (final l in _lists.values) {
      l.dispose();
    }
    _thresholdCtrl.dispose();
    for (final p in _procs) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDoctorInfo() async {
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/doctors/me'),
        ApiClient.instance.get('/doctors/me/prices'),
      ]);
      final me = results[0] as Map<String, dynamic>;
      final prices = results[1] as Map<String, dynamic>;
      final rules = List<Map<String, dynamic>>.from(prices['rules'] as List? ?? []);
      final procs = List<Map<String, dynamic>>.from(me['doctor_procedures'] as List? ?? [])
          .where((p) => p['active'] != false)
          .toList();
      String fmt(Object? v) => v is num ? v.toStringAsFixed(v % 1 == 0 ? 0 : 2) : '';
      setState(() {
        _offersOnline = me['offers_online_consult'] as bool? ?? false;
        _offersHome   = me['offers_home_visit']    as bool? ?? false;
        for (final r in rules) {
          final list = _lists['${r['channel']}|${r['visit_category']}'];
          final minutes = (r['duration_min'] as num).toInt();
          if (list == null || !_kLengths.contains(minutes)) continue;
          list.byLength[minutes] = TextEditingController(
              text: '${((r['price_paise'] as num) / 100).round()}');
        }
        _validityDays = (prices['follow_up_validity_days'] as num?)?.toInt();
        // A doctor setting prices for the first time starts from one
        // 15-minute first visit per channel, ready to fill in.
        for (final ch in [if (_offersOnline) 'online_consult', if (_offersHome) 'home_visit']) {
          final first = _list(ch, 'initial');
          if (first.byLength.isEmpty) first.toggle(15);
        }
        _thresholdCtrl.text = fmt(me['procedure_review_threshold']);
        if (procs.isNotEmpty) {
          for (final p in _procs) {
            p.dispose();
          }
          _procs
            ..clear()
            ..addAll(procs.map((p) => _ProcedureEntry(
                  id: p['id'] as String?,
                  name: p['name'] as String? ?? '',
                  price: fmt(p['price']),
                )));
        }
        _editing = rules.isNotEmpty;
        _loadingDoctorInfo = false;
      });
    } catch (_) {
      setState(() => _loadingDoctorInfo = false);
    }
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Prices: the whole list at once. Bookings already made keep theirs.
      final rules = [
        for (final ch in [if (_offersOnline) 'online_consult', if (_offersHome) 'home_visit'])
          for (final cat in ['initial', 'follow_up']) ..._list(ch, cat).toRules(),
      ];
      final hasFollowUp = rules.any((r) => r['visit_category'] == 'follow_up');
      await ApiClient.instance.put('/doctors/me/prices', {
        'rules': rules,
        'follow_up_validity_days': hasFollowUp ? _validityDays : null,
      });

      // Procedures: drop the removed ones, add only rows that are new.
      for (final id in _removedProcIds) {
        await ApiClient.instance.delete('/doctors/me/procedures/$id');
      }
      _removedProcIds.clear();
      for (final p in _procs.where((p) => p.id == null && p.valid)) {
        await ApiClient.instance.post('/doctors/me/procedures', {
          'name': p.nameCtrl.text.trim(),
          'price': double.parse(p.priceCtrl.text),
        });
      }

      // Threshold
      if (_thresholdCtrl.text.isNotEmpty) {
        await ApiClient.instance.patch('/doctors/me', {
          'procedure_review_threshold': double.parse(_thresholdCtrl.text),
        });
      }

      if (!mounted) return;
      if (_editing && context.canPop()) {
        showCharakToast(context, message: 'Prices saved');
        context.pop(true);
      } else {
        context.go('/home');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// One channel's prices: first-visit lengths and prices, then the
  /// optional follow-up ones. Lengths are chips; each picked length gets a
  /// price box.
  Widget _channelPrices(String label, String channel) {
    Widget list(_PriceList l, String title, String hint) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _fieldLabel),
        const SizedBox(height: 4),
        Text(hint, style: _suffix),
        const SizedBox(height: 8),
        CharakChipRow(children: [
          for (final m in _kLengths)
            CharakChip(
              label: '$m min',
              numeric: true,
              selected: l.byLength.containsKey(m),
              disabled: !l.byLength.containsKey(m) && l.byLength.length >= _kMaxLengths,
              onTap: () => setState(() => l.toggle(m)),
            ),
        ]),
        for (final m in (l.byLength.keys.toList()..sort())) ...[
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 64, child: Text('$m min', style: CharakText.body.tabular.copyWith(color: CharakColors.ink))),
            Text('₹', style: _rupee),
            const SizedBox(width: 10),
            Expanded(
              child: _PriceField(
                controller: l.byLength[m]!,
                hint: l.isFollowUp ? '0 for free' : '500',
                onChanged: () => setState(() {}),
              ),
            ),
          ]),
        ],
      ],
    );

    final followUp = _list(channel, 'follow_up');
    return Container(
      padding: const EdgeInsets.all(CharakSpacing.gutter),
      decoration: BoxDecoration(
        color: CharakColors.card,
        borderRadius: const BorderRadius.all(CharakRadius.card),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CharakSectionTitle(label: label),
        const SizedBox(height: 10),
        list(_list(channel, 'initial'), 'First visit', 'For a new problem. Pick up to $_kMaxLengths lengths.'),
        const SizedBox(height: 18),
        list(followUp, 'Follow-up (optional)',
            'For the same problem, after a visit with you. Leave empty if you don\'t offer one.'),
      ]),
    );
  }

  bool get _anyFollowUp => _lists.values.any((l) => l.isFollowUp && l.byLength.isNotEmpty);

  /// Why it can't be saved yet; null when it can.
  String? get _missing {
    for (final (ch, label) in [
      if (_offersOnline) ('online_consult', 'online consultations'),
      if (_offersHome) ('home_visit', 'home visits'),
    ]) {
      if (_list(ch, 'initial').byLength.isEmpty) return 'Pick a length for $label';
      if (!_list(ch, 'initial').complete) return 'Fill in each first-visit price (₹1–₹50,000)';
      if (!_list(ch, 'follow_up').complete) return 'Fill in each follow-up price (₹0 for free)';
    }
    if (_anyFollowUp && _validityDays == null) return 'Say how long a follow-up price applies';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Which channels this doctor offers decides which fee sections render, so
    // this is arriving content, not a pending action — `.skel` blocks keep the
    // step dots and heading in place while it loads.
    if (_loadingDoctorInfo) {
      return const CharakScreen(
        // Also reachable as a settings re-edit, pushed from the profile tab —
        // without this there is no way back on iOS.
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CharakStepDots(current: 2),
                SizedBox(height: 10),
                Text('Set your prices', style: CharakText.titleLarge),
                SizedBox(height: 5),
                CharakSkeleton(height: 14),
                SizedBox(height: 7),
                CharakSkeleton(width: 240, height: 14),
                SizedBox(height: 18),
                CharakSkeleton(height: 132, radius: 14),
                SizedBox(height: 12),
                CharakSkeleton(height: 132, radius: 14),
              ],
            ),
          ),
        ),
      );
    }

    final missing = _missing;

    return CharakScreen(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_editing) ...[
                      const CharakStepDots(current: 2),
                      const SizedBox(height: 10),
                    ],
                    Text(_editing ? 'Your prices' : 'Set your prices', style: CharakText.titleLarge),
                    const SizedBox(height: 5),
                    Text(
                      'Set a price for each length you offer. The patient picks the length '
                      'when they book. The whole fee goes to you. A change applies to new '
                      'bookings only.',
                      style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted),
                    ),
                    const SizedBox(height: 18),

                    if (_offersOnline) ...[
                      _channelPrices('Online consultation', 'online_consult'),
                      const SizedBox(height: 12),
                    ],
                    if (_offersHome) ...[
                      _channelPrices('Home visit', 'home_visit'),
                      const SizedBox(height: 12),
                    ],
                    if (_anyFollowUp) ...[
                      Text('A follow-up price applies for', style: _fieldLabel),
                      const SizedBox(height: 8),
                      CharakChipRow(children: [
                        for (final d in _kValidityDays)
                          CharakChip(
                            label: '$d days',
                            numeric: true,
                            selected: _validityDays == d,
                            onTap: () => setState(() => _validityDays = d),
                          ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        'after the visit, or until the follow-up date you recommend if that is later. '
                        'One follow-up per visit.',
                        style: _suffix,
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_offersHome) ...[

                      const CharakSectionTitle(label: 'Procedure prices · fixed'),
                      const SizedBox(height: 9),
                      Text(
                        "Shown to patients on your profile. Charged only after a home visit, "
                        "for what's actually done.",
                        style: CharakText.caption.copyWith(color: CharakColors.inkMuted, height: 1.5),
                      ),
                      const SizedBox(height: 12),

                      // Procedure row: a flat tile, name on the left, ₹ and a
                      // right-aligned price input on the right.
                      ..._procs.asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: CharakColors.card,
                            borderRadius: const BorderRadius.all(CharakRadius.tile),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: _PlainField(
                                controller: p.nameCtrl,
                                hint: 'e.g. ECG',
                                onChanged: () => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('₹', style: CharakText.body.tabular.copyWith(color: CharakColors.ink, fontWeight: FontWeight.w600, fontSize: 15)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 78,
                              child: _PriceField(
                                controller: p.priceCtrl,
                                hint: '250',
                                height: 38,
                                align: TextAlign.right,
                                onChanged: () => setState(() {}),
                              ),
                            ),
                            if (_procs.length > 1)
                              GestureDetector(
                                onTap: () {
                                  if (p.id != null) _removedProcIds.add(p.id!);
                                  p.dispose();
                                  setState(() => _procs.removeAt(i));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(LucideIcons.circleMinus,
                                      size: 18, color: CharakColors.danger),
                                ),
                              ),
                          ]),
                        );
                      }),
                      CharakGhostButton(
                        label: 'Add procedure',
                        icon: LucideIcons.plus,
                        onPressed: () => setState(() => _procs.add(_ProcedureEntry())),
                      ),

                      const SizedBox(height: 16),
                      const CharakSectionTitle(label: 'Senior review threshold'),
                      const SizedBox(height: 9),
                      Text('Review procedure bills above', style: _fieldLabel),
                      const SizedBox(height: 7),
                      Row(children: [
                        Text('₹', style: _rupee),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 120,
                          child: _PriceField(
                            controller: _thresholdCtrl,
                            hint: '500',
                            onChanged: () => setState(() {}),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 18),

                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
                    ],
                  ],
                ),
              ),
            ),
            CharakCtaBar(
              header: missing == null
                  ? null
                  : Text(missing, textAlign: TextAlign.center, style: charakHintStyle),
              children: [Expanded(child: CharakButton(
                label: _editing ? 'Save prices' : 'Finish — go live',
                onPressed: missing == null ? _submit : null,
                isLoading: _loading,
              ))],
            ),
          ],
        ),
      ),
    );
  }
}

/// `.field label` — 13px/600 ink.
final _fieldLabel = CharakText.caption.copyWith(color: CharakColors.ink, fontWeight: FontWeight.w600);

/// The 18px/600 rupee glyph that leads each price row.
final _rupee = CharakText.body.tabular.copyWith(color: CharakColors.ink, fontWeight: FontWeight.w600, fontSize: 18);

/// `.price-suffix` — 12.5px muted trailing unit.
final _suffix = CharakText.caption.copyWith(color: CharakColors.inkMuted);

/// `.input.tnum` — bordered numeric field on the control radius, tabular
/// figures. [height] drops to 38px for the compact `.proc-in` variant.
class _PriceField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final double height;
  final TextAlign align;
  final VoidCallback onChanged;
  const _PriceField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.height = 50,
    this.align = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: CharakColors.bg,
      borderRadius: const BorderRadius.all(CharakRadius.button),
      border: Border.all(color: CharakColors.borderStrong, width: 1.5),
    ),
    alignment: Alignment.center,
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: align,
      style: CharakText.body.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintText: hint,
        hintStyle: CharakText.body.copyWith(color: CharakColors.inkMuted),
      ),
      onChanged: (_) => onChanged(),
    ),
  );
}

/// Borderless 14px field used inside `.proc-price-row`, whose own border is
/// drawn by the row.
class _PlainField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  const _PlainField({required this.controller, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: CharakText.body.copyWith(fontSize: 14),
    decoration: InputDecoration(
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
      hintText: hint,
      hintStyle: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted),
    ),
    onChanged: (_) => onChanged(),
  );
}
