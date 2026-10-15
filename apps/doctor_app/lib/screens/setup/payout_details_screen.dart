import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

/// Where the doctor is paid: a UPI ID, a bank account, or both. Charak keeps
/// no fee, so every consult and procedure payment is passed on here.
class PayoutDetailsScreen extends StatefulWidget {
  const PayoutDetailsScreen({super.key});

  @override
  State<PayoutDetailsScreen> createState() => _PayoutDetailsScreenState();
}

class _PayoutDetailsScreenState extends State<PayoutDetailsScreen> {
  final _holderCtrl  = TextEditingController();
  final _upiCtrl     = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _ifscCtrl    = TextEditingController();
  final _bankCtrl    = TextEditingController();

  bool _fetching = true;
  bool _saving = false;
  String? _error;

  /// Masked number already on file ("••••9012"). The server never sends the
  /// full number back, so leaving the field blank keeps this one.
  String? _maskedAccount;
  bool _verified = false;

  static final _upiPattern = RegExp(r'^[a-zA-Z0-9._-]{2,256}@[a-zA-Z0-9]{2,64}$');
  static final _ifscPattern = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_holderCtrl, _upiCtrl, _accountCtrl, _ifscCtrl, _bankCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await ApiClient.instance.get('/payouts/me/bank-account') as Map<String, dynamic>;
      _holderCtrl.text = row['account_holder'] as String? ?? '';
      _upiCtrl.text    = row['upi_id'] as String? ?? '';
      _ifscCtrl.text   = row['ifsc'] as String? ?? '';
      _bankCtrl.text   = row['bank_name'] as String? ?? '';
      _maskedAccount   = row['account_number'] as String?;
      _verified        = row['verified'] as bool? ?? false;
    } on ApiException catch (e) {
      // 404 just means nothing saved yet.
      if (e.statusCode != 404) _error = e.message;
    } catch (_) {
      _error = 'Couldn\'t load your payout details';
    }
    if (mounted) setState(() => _fetching = false);
  }

  /// Client-side check mirroring the server's, so mistakes show before a
  /// round trip. Returns null when the form can be sent.
  String? _validate() {
    final upi = _upiCtrl.text.trim();
    final acct = _accountCtrl.text.trim();
    final ifsc = _ifscCtrl.text.trim().toUpperCase();
    final hasBank = acct.isNotEmpty || _maskedAccount != null;
    if (_holderCtrl.text.trim().length < 2) return 'Enter the account holder\'s name';
    if (upi.isNotEmpty && !_upiPattern.hasMatch(upi)) return 'UPI ID should look like name@bank';
    if (acct.isNotEmpty && !RegExp(r'^\d{6,20}$').hasMatch(acct)) return 'Account number should be 6–20 digits';
    if (hasBank && ifsc.isEmpty && acct.isNotEmpty) return 'Add the IFSC for this account';
    if (ifsc.isNotEmpty && !_ifscPattern.hasMatch(ifsc)) return 'IFSC should be 11 characters, e.g. HDFC0001234';
    if (ifsc.isNotEmpty && !hasBank) return 'Add the account number for this IFSC';
    if (upi.isEmpty && !(hasBank && ifsc.isNotEmpty)) return 'Add a UPI ID or a bank account';
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() { _saving = true; _error = null; });
    final acct = _accountCtrl.text.trim();
    final ifsc = _ifscCtrl.text.trim().toUpperCase();
    try {
      await ApiClient.instance.put('/payouts/me/bank-account', {
        'account_holder': _holderCtrl.text.trim(),
        'upi_id': _upiCtrl.text.trim().isEmpty ? null : _upiCtrl.text.trim(),
        if (acct.isNotEmpty) 'account_number': acct,
        'ifsc': ifsc.isEmpty ? null : ifsc,
        'bank_name': _bankCtrl.text.trim().isEmpty ? null : _bankCtrl.text.trim(),
      });
      if (!mounted) return;
      showCharakToast(context, message: 'Payout details saved');
      context.pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CharakScreen(
      title: 'Payout details',
      subtitle: 'Patients pay through CHARAK and the full fee is sent to you. '
          'Add a UPI ID, a bank account, or both.',
      bottom: CharakCtaBar.single(
        CharakButton(
          label: 'Save payout details',
          onPressed: _fetching ? null : _save,
          isLoading: _saving,
        ),
      ),
      body: _fetching
          ? const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(children: [
                CharakSkeleton(height: 60, radius: 20),
                SizedBox(height: 12),
                CharakSkeleton(height: 60, radius: 20),
                SizedBox(height: 12),
                CharakSkeleton(height: 60, radius: 20),
              ]),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_maskedAccount != null || _upiCtrl.text.isNotEmpty) ...[
                    CharakStatusPill(
                      label: _verified ? 'Verified by CHARAK' : 'Awaiting check by CHARAK',
                      tone: _verified ? CharakStatusTone.success : CharakStatusTone.warning,
                    ),
                    const SizedBox(height: 14),
                  ],
                  CharakField(
                    label: 'Account holder name',
                    placeholder: 'As on your bank / UPI',
                    controller: _holderCtrl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 22),
                  const CharakSectionTitle(label: 'UPI'),
                  const SizedBox(height: 9),
                  CharakField(
                    label: 'UPI ID',
                    placeholder: 'name@okhdfcbank',
                    hint: 'Fastest. Payouts land in the app you use for UPI.',
                    controller: _upiCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 22),
                  const CharakSectionTitle(label: 'Bank account'),
                  const SizedBox(height: 9),
                  CharakField(
                    label: 'Account number',
                    placeholder: _maskedAccount != null
                        ? '$_maskedAccount · leave blank to keep'
                        : '12–16 digits',
                    controller: _accountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    tabular: true,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  CharakField(
                    label: 'IFSC',
                    placeholder: 'HDFC0001234',
                    controller: _ifscCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [LengthLimitingTextInputFormatter(11)],
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  CharakField(
                    label: 'Bank name',
                    placeholder: 'Optional',
                    controller: _bankCtrl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Changing these details pauses payouts until CHARAK re-checks them.',
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
                  ],
                ],
              ),
            ),
    );
  }
}
