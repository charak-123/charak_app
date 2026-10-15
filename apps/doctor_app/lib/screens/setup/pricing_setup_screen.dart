import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

/// Lengths a doctor can charge for (5, 10, … 60 min), for a session and for
/// each extra-time block; matches SESSION_LENGTHS_MIN in
/// backend/app/routers/doctors.py.
final _kSessionLengths = [for (var m = 5; m <= 60; m += 5) m];

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
  // Consult fees
  final _onlineBaseCtrl  = TextEditingController();
  final _onlineExtraCtrl = TextEditingController();
  final _homeBaseCtrl    = TextEditingController();
  final _homeExtraCtrl   = TextEditingController();
  final _thresholdCtrl   = TextEditingController();

  int _onlineMins = 15, _homeMins = 15;
  int _onlineExtraMins = 15, _homeExtraMins = 15;

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
    _onlineBaseCtrl.dispose(); _onlineExtraCtrl.dispose();
    _homeBaseCtrl.dispose();   _homeExtraCtrl.dispose();
    _thresholdCtrl.dispose();
    for (final p in _procs) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDoctorInfo() async {
    try {
      final me = await ApiClient.instance.get('/doctors/me') as Map<String, dynamic>;
      final pricing = List<Map<String, dynamic>>.from(me['doctor_pricing'] as List? ?? []);
      final procs = List<Map<String, dynamic>>.from(me['doctor_procedures'] as List? ?? [])
          .where((p) => p['active'] != false)
          .toList();
      String fmt(Object? v) => v is num ? v.toStringAsFixed(v % 1 == 0 ? 0 : 2) : '';
      void fill(String channel, TextEditingController base, TextEditingController extra,
          void Function(int) setMins, void Function(int) setExtraMins) {
        final row = pricing.where((p) => p['channel'] == channel).firstOrNull;
        if (row == null) return;
        base.text = fmt(row['price']);
        final x = row['extra_rate_per_15min'];
        extra.text = x is num && x > 0 ? fmt(x) : '';
        final mins = (row['base_duration_min'] as num?)?.toInt();
        if (mins != null && _kSessionLengths.contains(mins)) setMins(mins);
        final extraMins = (row['extra_duration_min'] as num?)?.toInt();
        if (extraMins != null && _kSessionLengths.contains(extraMins)) setExtraMins(extraMins);
      }
      setState(() {
        _offersOnline = me['offers_online_consult'] as bool? ?? false;
        _offersHome   = me['offers_home_visit']    as bool? ?? false;
        fill('online_consult', _onlineBaseCtrl, _onlineExtraCtrl, (m) => _onlineMins = m,
            (m) => _onlineExtraMins = m);
        fill('home_visit', _homeBaseCtrl, _homeExtraCtrl, (m) => _homeMins = m,
            (m) => _homeExtraMins = m);
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
        _editing = pricing.isNotEmpty;
        _loadingDoctorInfo = false;
      });
    } catch (_) {
      setState(() => _loadingDoctorInfo = false);
    }
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Pricing
      final pricingItems = <Map<String, dynamic>>[];
      if (_offersOnline) {
        pricingItems.add({
          'channel': 'online_consult',
          'price': double.parse(_onlineBaseCtrl.text),
          'base_duration_min': _onlineMins,
          'extra_duration_min': _onlineExtraMins,
          'extra_rate_per_15min': double.tryParse(_onlineExtraCtrl.text) ?? 0,
        });
      }
      if (_offersHome) {
        pricingItems.add({
          'channel': 'home_visit',
          'price': double.parse(_homeBaseCtrl.text),
          'base_duration_min': _homeMins,
          'extra_duration_min': _homeExtraMins,
          'extra_rate_per_15min': double.tryParse(_homeExtraCtrl.text) ?? 0,
        });
      }
      await ApiClient.instance.put('/doctors/me/pricing', pricingItems);

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

  /// One consult-fee block: `.field` label, then the base-price row
  /// (18px ₹ + flexible input + `.price-suffix`) and the 86px extra-rate row.
  Widget _feeSection(String label, TextEditingController baseCtrl, TextEditingController extraCtrl,
      int mins, ValueChanged<int> onMins, int extraMins, ValueChanged<int> onExtraMins) {
    Widget lengths(int value, ValueChanged<int> onPick) => CharakChipRow(children: [
      for (final m in _kSessionLengths)
        CharakChip(label: '$m min', numeric: true, selected: m == value, onTap: () => onPick(m)),
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _fieldLabel),
        const SizedBox(height: 7),
        Text('Session length', style: _suffix),
        const SizedBox(height: 6),
        lengths(mins, onMins),
        const SizedBox(height: 10),
        Row(children: [
          Text('₹', style: _rupee),
          const SizedBox(width: 10),
          Expanded(
            child: _PriceField(
              controller: baseCtrl,
              hint: '500',
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          Text('per $mins min', style: _suffix),
        ]),
        const SizedBox(height: 14),
        Text('Extra time, charged per', style: _suffix),
        const SizedBox(height: 6),
        lengths(extraMins, onExtraMins),
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(
            width: 86,
            child: _PriceField(
              controller: extraCtrl,
              hint: '150',
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          Text('per extra $extraMins min', style: _suffix),
        ]),
      ],
    );
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

    final onlineValid = !_offersOnline || (_onlineBaseCtrl.text.isNotEmpty);
    final homeValid   = !_offersHome   || (_homeBaseCtrl.text.isNotEmpty);

    final onlineShown = _onlineBaseCtrl.text.isNotEmpty ? _onlineBaseCtrl.text : '—';
    final homeShown   = _homeBaseCtrl.text.isNotEmpty ? _homeBaseCtrl.text : '—';

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
                      'Pick how long one session is and what it costs, and how extra '
                      'time is charged. The whole fee goes to you.',
                      style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted),
                    ),
                    const SizedBox(height: 18),

                    if (_offersOnline) ...[
                      _feeSection('Online consult', _onlineBaseCtrl, _onlineExtraCtrl,
                          _onlineMins, (m) => setState(() => _onlineMins = m),
                          _onlineExtraMins, (m) => setState(() => _onlineExtraMins = m)),
                      const SizedBox(height: 12),
                    ],
                    if (_offersHome) ...[
                      _feeSection('Home visit', _homeBaseCtrl, _homeExtraCtrl,
                          _homeMins, (m) => setState(() => _homeMins = m),
                          _homeExtraMins, (m) => setState(() => _homeExtraMins = m)),
                      const SizedBox(height: 14),

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

                      // `.price-preview` — bgSubtle block, 13px/1.55 muted with
                      // the figures lifted to ink.
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: CharakColors.bgSubtle,
                          borderRadius: const BorderRadius.all(CharakRadius.card),
                        ),
                        child: Text.rich(
                          TextSpan(
                            style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                            children: [
                              const TextSpan(text: 'Patients see '),
                              TextSpan(text: '₹$onlineShown / $_onlineMins min', style: _previewStrong),
                              const TextSpan(text: ' online and '),
                              TextSpan(text: '₹$homeShown / $_homeMins min', style: _previewStrong),
                              const TextSpan(
                                text: ' for home visits — plus your fixed '
                                    'procedure rates and the senior-review note.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
                    ],
                  ],
                ),
              ),
            ),
            CharakCtaBar.single(
              CharakButton(
                label: _editing ? 'Save prices' : 'Finish — go live',
                onPressed: (onlineValid && homeValid) ? _submit : null,
                isLoading: _loading,
              ),
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

/// `.price-preview b` — the figures inside the preview block.
final _previewStrong = TextStyle(
  color: CharakColors.ink,
  fontWeight: FontWeight.w600,
);

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
