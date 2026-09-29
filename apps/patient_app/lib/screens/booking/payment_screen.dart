import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:charak_core/charak_core.dart';

/// Consult-fee payment.
///
/// Two things shape this screen.
///
/// **The gateway owns method selection, not us.** Card details are never typed
/// into our own fields — that would put the app inside PCI scope for no benefit.
/// Razorpay's checkout collects them, and on Android it also renders the UPI app
/// chooser (GPay / PhonePe / Paytm) natively, which is the whole reason UPI intent
/// is the default there.
///
/// **The return trip is not proof of payment.** On UPI the patient leaves for
/// another app and may never come back — killing ours mid-payment is ordinary, and
/// on iOS the app-switch back is the least reliable link in the chain. So
/// `_onSuccess` is treated as a hint to wait, and the booking's own row, streamed
/// from Supabase, is what actually confirms. The backend flips it to `paid` only
/// on a signature-verified Razorpay webhook.
class PaymentScreen extends ConsumerStatefulWidget {
  final String bookingId;

  /// "consult_fee" or "procedure_bill". The backend prices the order from
  /// this, and defaults to the consult fee — so a procedure bill that did not
  /// pass it was priced as a consult, charging the wrong amount for the wrong
  /// thing.
  final String type;

  const PaymentScreen({
    super.key,
    required this.bookingId,
    this.type = 'consult_fee',
  });
  @override
  ConsumerState<PaymentScreen> createState() => _State();
}

/// Android gets a real intent chooser, so UPI-only is a clean default there.
/// iOS has no chooser — Razorpay can only deep-link UPI apps one at a time, and
/// coverage is patchier — so restricting methods would strip every fallback at
/// exactly the point where UPI is least reliable. iOS sees the full sheet.
bool get _upiIntentAvailable => Platform.isAndroid;

class _State extends ConsumerState<PaymentScreen> {
  bool _loading = false;
  bool _awaitingConfirmation = false;
  Map<String, dynamic>? _order;
  final _upiCtrl = TextEditingController();

  Razorpay? _razorpay;
  CharakPoller? _bookingPoll;
  Timer? _confirmationTimeout;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _createOrder();
    _watchBooking();
  }

  @override
  void dispose() {
    // Razorpay holds a native handler; clear() is not optional.
    _razorpay?.clear();
    _bookingPoll?.dispose();
    _confirmationTimeout?.cancel();
    _upiCtrl.dispose();
    super.dispose();
  }

  // ── Order ───────────────────────────────────────────────────────────────────

  Future<void> _createOrder() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.post(
          '/payments/${widget.bookingId}/order', {'type': widget.type});
      setState(() => _order = res as Map<String, dynamic>);
    } on ApiException catch (e) {
      _fail(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Confirmation ────────────────────────────────────────────────────────────

  /// The authoritative signal. Runs from the moment the screen opens, so a
  /// payment that lands while the patient is still in GPay is caught either way.
  ///
  /// This polls the backend rather than subscribing to Supabase realtime. The
  /// apps hold only the anon key and authenticate with a FastAPI JWT, so
  /// `auth.uid()` is NULL for them — and every bookings RLS policy in
  /// migration 0004 is `patient_id = auth.uid()`. A realtime subscription
  /// therefore matched no rows and never fired, which left every live payment
  /// sitting on "taking longer than usual" even when it had succeeded.
  void _watchBooking() {
    // Payment resolves in seconds, so this starts tight. The 90s timeout is
    // what gives up, long before the backoff matters.
    _bookingPoll = CharakPoller(
      interval: const Duration(seconds: 3),
      maxInterval: const Duration(seconds: 15),
      onPoll: () async {
        if (!mounted) return true;
        final b = await ApiClient.instance.get('/bookings/${widget.bookingId}')
            as Map<String, dynamic>;
        if (!mounted) return true;
        final status = b['status'] as String? ?? '';
        if (status == 'paid') {
          _stopWatching();
          context.go('/booking/${widget.bookingId}/confirmed');
          return true;
        }
        if (status == 'cancelled' || status == 'declined') {
          // The hold expired while the patient was away, or the doctor
          // withdrew. Any money that lands now is refunded by the backend, so
          // say so here rather than leaving them on a dead payment screen.
          _stopWatching();
          context.go('/booking/${widget.bookingId}/status');
          return true;
        }
        return false;
      },
    )..start();
  }

  void _stopWatching() {
    _bookingPoll?.stop();
    _confirmationTimeout?.cancel();
  }

  // ── Pay ─────────────────────────────────────────────────────────────────────

  Future<void> _pay({String? vpa}) async {
    final order = _order;
    if (order == null) return;

    final key = order['razorpay_key'] as String? ?? '';
    if (key.startsWith('stub')) {
      // No credentials configured — complete it server-side so the rest of the
      // journey is walkable in development.
      setState(() => _loading = true);
      try {
        await ApiClient.instance.post(
            '/payments/${widget.bookingId}/stub-complete',
            {'type': widget.type});
        if (mounted) context.go('/booking/${widget.bookingId}/confirmed');
      } on ApiException catch (e) {
        _fail(e.message);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    _razorpay?.open({
      'key': key,
      'order_id': order['razorpay_order_id'],
      'amount': order['amount'],
      'currency': order['currency'] ?? 'INR',
      'name': 'Charak',
      'description': 'Consultation fee',
      'timeout': 300,
      if (_upiIntentAvailable)
        'method': {
          'upi': true,
          'card': false,
          'netbanking': false,
          'wallet': false,
        },
      // UPI collect: the request appears inside the patient's UPI app, with no
      // app-switch and no return trip to depend on. Only worth offering where
      // intent is unavailable.
      if (vpa != null && vpa.isNotEmpty) 'vpa': vpa,
    });
  }

  void _onSuccess(PaymentSuccessResponse r) {
    // Not proof — see the class doc. Wait for the booking row.
    if (!mounted) return;
    setState(() => _awaitingConfirmation = true);
    _confirmationTimeout = Timer(const Duration(seconds: 90), () {
      if (mounted && _awaitingConfirmation) {
        setState(() => _awaitingConfirmation = false);
        _fail('Payment is taking longer than usual to confirm. '
            'Check your bookings in a moment — do not pay again.');
      }
    });
  }

  void _onError(PaymentFailureResponse r) {
    // Tells the backend to keep the slot held for the rest of the window.
    ApiClient.instance
        .post('/payments/${widget.bookingId}/failed', {})
        .catchError((_) => null);
    if (mounted) {
      setState(() => _awaitingConfirmation = false);
      _fail('Payment did not go through. Your slot is still held — try again.');
    }
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    if (mounted) setState(() => _awaitingConfirmation = true);
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: CharakColors.danger),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final amount = _order != null ? (_order!['amount'] as int) / 100 : 0.0;
    final isStub =
        (_order?['razorpay_key'] as String? ?? '').startsWith('stub');

    return Scaffold(
      backgroundColor: CharakColors.ground,
      appBar: const CharakTopBar(title: 'Payment'),
      body: _loading && _order == null
          // Initial order fetch — content is arriving, so `.skel` stands in.
          ? const _PaymentLoading()
          : Column(children: [
              Expanded(child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  // `.sheet-title` row — amount left, "Secure" badge right.
                  Row(children: [
                    Expanded(
                      child: Text('Pay ₹${amount.toStringAsFixed(0)}',
                          style: CharakText.h2.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                    ),
                    const CharakBadge(
                        label: 'Secure',
                        variant: CharakBadgeVariant.muted,
                        icon: Icons.lock_outline),
                  ]),
                  const SizedBox(height: 4),
                  Text('Consultation fee · paid before the visit',
                      style: charakHintStyle),
                  const SizedBox(height: 18),

                  if (_awaitingConfirmation)
                    const CharakNoteBanner(
                      icon: Icons.hourglass_top_outlined,
                      tone: CharakStatusTone.primary,
                      message: 'Confirming your payment with the bank. This can '
                          'take a few seconds — please stay on this screen.',
                    )
                  else ...[
                    CharakNoteBanner(
                      icon: _upiIntentAvailable
                          ? Icons.account_balance_wallet_outlined
                          : Icons.lock_outline,
                      tone: CharakStatusTone.primary,
                      message: _upiIntentAvailable
                          ? 'Tap Pay to choose your UPI app — GPay, PhonePe, '
                              'Paytm or any other installed app.'
                          : 'Tap Pay to choose how you would like to pay — UPI, '
                              'card, or net banking.',
                    ),

                    // iOS only: no intent chooser exists, so offer collect as a
                    // fallback that does not depend on deep-linking working.
                    if (!_upiIntentAvailable) ...[
                      const SizedBox(height: 18),
                      CharakField(
                        label: 'Pay by UPI ID',
                        controller: _upiCtrl,
                        placeholder: 'yourname@bank',
                        hint: 'We will send a request to your UPI app',
                      ),
                      const SizedBox(height: 10),
                      CharakButton(
                        label: 'Request via UPI ID',
                        outlined: true,
                        onPressed: _order == null
                            ? null
                            : () => _pay(vpa: _upiCtrl.text.trim()),
                      ),
                    ],
                  ],

                  const SizedBox(height: 14),
                  const CharakNoteBanner(
                    icon: Icons.verified_user_outlined,
                    tone: CharakStatusTone.success,
                    message: 'Payment is processed securely via Razorpay. The '
                        'booking is confirmed the moment payment lands.',
                  ),
                ],
              )),

              CharakCtaBar.single(
                CharakButton(
                  label: isStub
                      ? 'Confirm payment (dev stub)'
                      : 'Pay ₹${amount.toStringAsFixed(0)}',
                  isLoading: _loading || _awaitingConfirmation,
                  onPressed:
                      _order != null && !_awaitingConfirmation ? _pay : null,
                ),
              ),
            ]),
    );
  }
}

/// Loading state for the initial order fetch: `.skel` blocks in the shape of the
/// amount header and the guidance banners below it.
class _PaymentLoading extends StatelessWidget {
  const _PaymentLoading();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          CharakSkeleton(width: 148, height: 21),
          Spacer(),
          CharakSkeleton(width: 78, height: 22, radius: 11),
        ]),
        SizedBox(height: 10),
        CharakSkeleton(width: 234, height: 13),
        SizedBox(height: 18),
        CharakSkeleton(height: 62, radius: 12),
        SizedBox(height: 14),
        CharakSkeleton(height: 62, radius: 12),
      ],
    ),
  );
}
