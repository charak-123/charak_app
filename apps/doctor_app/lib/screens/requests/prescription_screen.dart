import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:image_picker/image_picker.dart';
// intl is a direct dependency; don't rely on shadcn_ui re-exporting DateFormat.
// ignore: unnecessary_import
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Everything the screen needs: the booking, what the doctor is working on (a
/// draft, else the sent prescription), the sent one while a correction is
/// being written, and whether the doctor has a signature on file.
final _rxProvider = FutureProvider.autoDispose.family<_RxData, String>((ref, bookingId) async {
  final results = await Future.wait([
    ApiClient.instance.get('/bookings/$bookingId'),
    ApiClient.instance.get('/bookings/$bookingId/prescription'),
    ApiClient.instance.get('/doctors/me'),
  ]);
  final rx = results[1] as Map<String, dynamic>;
  return _RxData(
    booking: results[0] as Map<String, dynamic>,
    current: rx['prescription'] is Map
        ? CharakPrescription.fromJson((rx['prescription'] as Map).cast<String, dynamic>())
        : null,
    hasSignature: ((results[2] as Map)['signature_path'] as String?)?.isNotEmpty ?? false,
  );
});

class _RxData {
  final Map<String, dynamic> booking;
  final CharakPrescription? current;
  final bool hasSignature;
  const _RxData({required this.booking, required this.current, required this.hasSignature});
}

/// The doctor writes the prescription (or consultation notes), reviews it,
/// and sends it. Once sent it can't change: a mistake is fixed by issuing a
/// correction, a new version the patient also receives, and the original
/// stays on record.
class PrescriptionScreen extends ConsumerWidget {
  final String bookingId;
  const PrescriptionScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_rxProvider(bookingId));
    return async.when(
      loading: () => const CharakScreen(
        title: 'Prescription',
        body: SingleChildScrollView(child: CharakSkeletonDetail()),
      ),
      error: (e, _) => CharakScreen(
        title: 'Prescription',
        body: CharakErrorState(error: e, onRetry: () => ref.invalidate(_rxProvider(bookingId))),
      ),
      data: (data) {
        final rx = data.current;
        if (rx != null && !rx.isDraft) {
          return _SentView(bookingId: bookingId, data: data, rx: rx);
        }
        return _Composer(bookingId: bookingId, data: data, draft: rx);
      },
    );
  }
}

// ── The sent prescription ───────────────────────────────────────────────────

class _SentView extends ConsumerStatefulWidget {
  final String bookingId;
  final _RxData data;
  final CharakPrescription rx;
  const _SentView({required this.bookingId, required this.data, required this.rx});

  @override
  ConsumerState<_SentView> createState() => _SentViewState();
}

class _SentViewState extends ConsumerState<_SentView> {
  bool _busy = false;

  Future<void> _correct() async {
    final ok = await showCharakConfirm(
      context,
      title: 'Issue a correction?',
      message: 'You get a copy of this prescription to change. When you send it, the patient '
          'is told and sees the corrected version. This one stays on record.',
      confirmLabel: 'Start correction',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ApiClient.instance.post('/prescriptions/${widget.rx.id}/correct', {});
      ref.invalidate(_rxProvider(widget.bookingId));
    } on ApiException catch (e) {
      if (mounted) showCharakToast(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPdf() async {
    try {
      final files = await ApiClient.instance.get('/prescriptions/${widget.rx.id}/files') as Map;
      final url = files['pdf_url'] as String?;
      if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on ApiException catch (e) {
      if (mounted) showCharakToast(context, message: e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = widget.rx;
    final sent = rx.submittedAt;
    final viewed = rx.firstViewedAt;
    return CharakScreen(
      title: rx.isNotes ? 'Consultation notes' : 'Prescription',
      subtitle: [
        if (rx.version > 1) 'Version ${rx.version}',
        if (sent != null) 'Sent ${CharakFormat.dayTime(sent)}',
      ].join(' · '),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 4, CharakSpacing.gutter, 32),
        children: [
          CharakInfoStrip(
            icon: viewed != null ? LucideIcons.eye : LucideIcons.send,
            label: viewed != null ? 'Opened by the patient' : 'Not opened yet',
            value: viewed != null ? CharakFormat.dayTime(viewed) : null,
            tone: viewed != null ? CharakStatusTone.confirmed : CharakStatusTone.muted,
            tabularValue: true,
          ),
          const SizedBox(height: 12),
          CharakPrescriptionView(prescription: rx),
          if (rx.hasPdf)
            CharakButton(
              label: 'Open PDF',
              icon: LucideIcons.fileText,
              variant: CharakButtonVariant.outline,
              onPressed: _openPdf,
            ),
        ],
      ),
      bottom: CharakCtaBar(
        header: Text('A sent prescription can’t be edited. Corrections are a new version.',
            textAlign: TextAlign.center, style: charakHintStyle),
        children: [
          Expanded(
            child: CharakButton(
              label: 'Issue a correction',
              icon: LucideIcons.filePen,
              variant: CharakButtonVariant.tonal,
              isLoading: _busy,
              onPressed: _correct,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Writing it ───────────────────────────────────────────────────────────────

class _Composer extends ConsumerStatefulWidget {
  final String bookingId;
  final _RxData data;
  final CharakPrescription? draft;
  const _Composer({required this.bookingId, required this.data, required this.draft});

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  late String _kind;
  String? _sex;
  late final TextEditingController _age;
  late final TextEditingController _complaints;
  late final TextEditingController _diagnosis;
  late final TextEditingController _investigations;
  late final TextEditingController _advice;
  late final TextEditingController _followNote;
  late List<CharakMedicine> _items;
  late bool _tpg;
  late bool _hasUpload;
  bool _followUp = false;
  DateTime? _followDate;
  String _followChannel = 'either';

  bool _reviewing = false;
  bool _busy = false;
  String? _error;

  bool get _online => widget.data.booking['channel'] == 'online_consult';

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _kind = d?.kind ?? 'prescription';
    _sex = d?.patientSex;
    _age = TextEditingController(text: d?.patientAge?.toString() ?? '');
    _complaints = TextEditingController(text: d?.complaints ?? '');
    _diagnosis = TextEditingController(text: d?.diagnosis ?? '');
    _investigations = TextEditingController(text: d?.investigations ?? '');
    _advice = TextEditingController(text: d?.advice ?? '');
    _items = [...?d?.items];
    _tpg = d?.tpgAttested ?? false;
    _hasUpload = d?.hasUpload ?? false;
    final f = d?.followUp;
    _followUp = f != null && !f.date.isBefore(_today);
    _followDate = _followUp ? f!.date : null;
    _followChannel = f?.channel ?? 'either';
    _followNote = TextEditingController(text: f?.note ?? '');
  }

  @override
  void dispose() {
    for (final c in [_age, _complaints, _diagnosis, _investigations, _advice, _followNote]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Map<String, dynamic> get _draftJson => {
        'kind': _kind,
        'patient_age': int.tryParse(_age.text.trim()),
        'patient_sex': _sex,
        'complaints': _t(_complaints),
        'diagnosis': _t(_diagnosis),
        'investigations': _t(_investigations),
        'advice': _t(_advice),
        'tpg_attested': _tpg,
        'items': _kind == 'notes' ? <Map<String, dynamic>>[] : _items.map((m) => m.toJson()).toList(),
      };

  CharakFollowUp? get _followUpValue => _followUp && _followDate != null
      ? CharakFollowUp(date: _followDate!, channel: _followChannel, note: _t(_followNote))
      : null;

  /// What the patient will see, built from the form as it stands.
  CharakPrescription get _preview => CharakPrescription(
        id: widget.draft?.id ?? '',
        bookingId: widget.bookingId,
        kind: _kind,
        complaints: _t(_complaints),
        diagnosis: _t(_diagnosis),
        investigations: _t(_investigations),
        advice: _t(_advice),
        hasUpload: _hasUpload,
        items: _kind == 'notes' ? const [] : _items,
        followUp: _followUpValue,
      );

  /// Why it can't be sent yet, in the doctor's terms; null when it can.
  String? get _missing {
    if (_kind == 'notes') {
      return [_advice, _complaints, _diagnosis].every((c) => c.text.trim().isEmpty)
          ? 'Write the advice or findings for the patient'
          : null;
    }
    if (_items.isEmpty && !_hasUpload) return 'Add a medicine or attach a handwritten prescription';
    if (_online && !_tpg) return 'Confirm the Telemedicine Practice Guidelines below';
    if (_followUp && _followDate == null) return 'Pick the follow-up date';
    return null;
  }

  Future<bool> _save() async {
    try {
      await ApiClient.instance.put('/bookings/${widget.bookingId}/prescription', _draftJson);
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    }
  }

  Future<void> _toReview() async {
    setState(() { _busy = true; _error = null; });
    final ok = await _save();
    if (!mounted) return;
    setState(() { _busy = false; _reviewing = ok; });
  }

  Future<void> _send() async {
    final ok = await showCharakConfirm(
      context,
      title: widget.draft?.isCorrection == true ? 'Send the correction?' : 'Send to the patient?',
      message: "They're notified and can open it in CHARAK. After this it can't be edited; "
          'a mistake is fixed with a correction.',
      confirmLabel: 'Send',
    );
    if (!ok || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      // Saved again first, so what is sent is exactly what was reviewed.
      if (!await _save()) return;
      await ApiClient.instance.post('/bookings/${widget.bookingId}/prescription/submit', {
        'follow_up': _followUpValue?.toSubmitJson(),
      });
      if (!mounted) return;
      showCharakToast(context, message: 'Sent. The patient has been notified.');
      context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _reviewing = false; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaving keeps what was typed: the draft is saved on the way out.
  Future<void> _back() async {
    if (_reviewing) {
      setState(() => _reviewing = false);
      return;
    }
    await _save();
    if (mounted) context.pop();
  }

  Future<void> _editMedicine([int? index]) async {
    final result = await showCharakSheet<CharakMedicine>(
      context,
      title: index == null ? 'Add medicine' : 'Edit medicine',
      child: _MedicineForm(initial: index == null ? null : _items[index]),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _items = [..._items, result];
      } else {
        _items = [..._items]..[index] = result;
      }
    });
  }

  Future<void> _attach() async {
    final source = await showCharakSheet<String>(
      context,
      title: 'Handwritten prescription',
      child: Builder(
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CharakButton(label: 'Take a photo', icon: LucideIcons.camera, onPressed: () => Navigator.pop(ctx, 'camera')),
          const SizedBox(height: 8),
          CharakButton(label: 'Choose a photo', icon: LucideIcons.image,
              variant: CharakButtonVariant.outline, onPressed: () => Navigator.pop(ctx, 'gallery')),
          const SizedBox(height: 8),
          CharakButton(label: 'Choose a PDF', icon: LucideIcons.fileText,
              variant: CharakButtonVariant.outline, onPressed: () => Navigator.pop(ctx, 'pdf')),
        ]),
      ),
    );
    if (source == null || !mounted) return;

    List<int>? bytes;
    String? name;
    String? type;
    if (source == 'pdf') {
      final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: const ['pdf'], withData: true);
      final f = picked?.files.single;
      if (f?.bytes == null) return;
      bytes = f!.bytes;
      name = f.name;
      type = 'application/pdf';
    } else {
      final photo = await ImagePicker().pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2400,
      );
      if (photo == null) return;
      bytes = await photo.readAsBytes();
      name = photo.name;
      final ext = photo.path.split('.').last.toLowerCase();
      type = 'image/${ext == 'jpg' ? 'jpeg' : ext}';
    }
    if (!mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _save();   // the upload attaches to the draft as saved
      await ApiClient.instance.postFile('/bookings/${widget.bookingId}/prescription/upload',
          bytes: bytes!, filename: name, contentType: type);
      if (mounted) setState(() => _hasUpload = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeUpload() async {
    setState(() => _busy = true);
    try {
      await ApiClient.instance.delete('/bookings/${widget.bookingId}/prescription/upload');
      if (mounted) setState(() => _hasUpload = false);
    } on ApiException catch (e) {
      if (mounted) showCharakToast(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFollowDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _followDate ?? _today.add(const Duration(days: 7)),
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _followDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final patient = (widget.data.booking['users'] as Map?)?['name'] as String? ?? 'Patient';
    final correction = widget.draft?.isCorrection == true;
    final missing = _missing;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: CharakScreen(
        title: _reviewing ? 'Check before sending' : (correction ? 'Correction' : 'Prescription'),
        subtitle: correction ? '$patient · version ${widget.draft!.version}' : patient,
        onBack: _back,
        body: CharakFadeSwap(
          child: _reviewing
              ? ListView(
                  key: const ValueKey('review'),
                  padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 4, CharakSpacing.gutter, 32),
                  children: [
                    CharakPrescriptionView(prescription: _preview),
                    if (!widget.data.hasSignature)
                      const CharakNoteBanner(
                        icon: LucideIcons.signature,
                        leadLabel: 'No signature on file.',
                        message: ' The PDF carries your name and registration. Add a signature in Profile.',
                      ),
                    if (_error != null) ...[const SizedBox(height: 12), _ErrorLine(_error!)],
                  ],
                )
              : _form(context),
        ),
        bottom: CharakCtaBar(
          header: Text(
            _reviewing
                ? 'The patient sees exactly this, and a PDF of it.'
                : (missing ?? 'Next, check it over before it goes'),
            textAlign: TextAlign.center,
            style: charakHintStyle,
          ),
          children: [
            Expanded(
              child: _reviewing
                  ? CharakButton(label: 'Send to patient', icon: LucideIcons.send, isLoading: _busy, onPressed: _send)
                  : CharakButton(
                      label: 'Review',
                      trailingIcon: LucideIcons.arrowRight,
                      isLoading: _busy,
                      onPressed: missing == null ? _toReview : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(BuildContext context) => ListView(
        key: const ValueKey('form'),
        padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 4, CharakSpacing.gutter, 32),
        children: [
          CharakSegmented<String>(
            segments: const [
              CharakSegment(value: 'prescription', label: 'Prescription'),
              CharakSegment(value: 'notes', label: 'Notes only'),
            ],
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
          if (_kind == 'notes') ...[
            const SizedBox(height: 8),
            Text('For a consultation that needed no medicines: your findings and advice.',
                style: charakHintStyle),
          ],
          const SizedBox(height: 24),
          const CharakSectionTitle(label: 'Patient'),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 104,
              child: CharakField(
                label: 'Age',
                controller: _age,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                tabular: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (v, l) in const [('female', 'Female'), ('male', 'Male'), ('other', 'Other')])
                  CharakChip(label: l, selected: _sex == v,
                      onTap: () => setState(() => _sex = _sex == v ? null : v)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          CharakField(label: 'Complaints', controller: _complaints, maxLines: 4, minLines: 2,
              textCapitalization: TextCapitalization.sentences, onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          CharakField(label: 'Provisional diagnosis', controller: _diagnosis, maxLines: 3, minLines: 1,
              textCapitalization: TextCapitalization.sentences, onChanged: (_) => setState(() {})),
          if (_kind == 'prescription') ...[
            const SizedBox(height: 24),
            CharakSectionTitle(label: 'Medicines', trailing: Text('${_items.length}', style: CharakText.caption.tabular)),
            const SizedBox(height: 8),
            if (_items.isNotEmpty)
              CharakCard(
                padding: const EdgeInsets.symmetric(horizontal: CharakSpacing.gutter, vertical: 4),
                child: Column(children: [
                  for (var i = 0; i < _items.length; i++)
                    CharakPressable(
                      onTap: () => _editMedicine(i),
                      child: CharakMedicineLine(
                        medicine: _items[i],
                        last: i == _items.length - 1,
                        trailing: CharakRoundIconButton(
                          icon: LucideIcons.x,
                          semanticLabel: 'Remove ${_items[i].medicine}',
                          onTap: () => setState(() => _items = [..._items]..removeAt(i)),
                        ),
                      ),
                    ),
                ]),
              ),
            const SizedBox(height: 10),
            CharakButton(
              label: 'Add medicine',
              icon: LucideIcons.plus,
              variant: CharakButtonVariant.tonal,
              onPressed: _items.length >= 30 ? null : () => _editMedicine(),
            ),
            const SizedBox(height: 10),
            _hasUpload
                ? CharakListRow(
                    icon: LucideIcons.fileCheck,
                    title: 'Handwritten prescription attached',
                    subtitle: 'The patient gets it with the prescription',
                    showChevron: false,
                    last: true,
                    trailing: CharakGhostButton(label: 'Remove', onPressed: _busy ? null : _removeUpload),
                  )
                : CharakButton(
                    label: 'Attach handwritten prescription',
                    icon: LucideIcons.paperclip,
                    variant: CharakButtonVariant.outline,
                    isLoading: _busy,
                    onPressed: _attach,
                  ),
          ],
          const SizedBox(height: 24),
          CharakField(label: 'Investigations', placeholder: 'Tests to get done, if any',
              controller: _investigations, maxLines: 3, minLines: 1,
              textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: 12),
          CharakField(label: 'Advice', controller: _advice, maxLines: 6, minLines: 2,
              textCapitalization: TextCapitalization.sentences, onChanged: (_) => setState(() {})),
          const SizedBox(height: 24),
          CharakToggleCard(
            icon: LucideIcons.calendarClock,
            title: 'Recommend a follow-up',
            subtitle: 'The patient is reminded and can book it. Nothing is booked for them.',
            value: _followUp,
            onChanged: (v) => setState(() => _followUp = v),
          ),
          if (_followUp) ...[
            const SizedBox(height: 12),
            CharakListRow(
              icon: LucideIcons.calendar,
              title: _followDate == null ? 'Pick a date' : DateFormat('EEE d MMM y').format(_followDate!),
              subtitle: 'Around this date',
              last: true,
              onTap: _pickFollowDate,
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (v, l) in const [('online_consult', 'Online'), ('home_visit', 'Home visit'), ('either', 'Either')])
                CharakChip(label: l, selected: _followChannel == v,
                    onTap: () => setState(() => _followChannel = v)),
            ]),
            const SizedBox(height: 10),
            CharakField(label: 'Note for the patient', placeholder: 'Optional',
                controller: _followNote, maxLines: 3, minLines: 1,
                textCapitalization: TextCapitalization.sentences),
          ],
          if (_online && _kind == 'prescription') ...[
            const SizedBox(height: 20),
            CharakCheckRow(
              value: _tpg,
              onChanged: (v) => setState(() => _tpg = v),
              label: 'I prescribed within the Telemedicine Practice Guidelines 2020 '
                  'for a video consultation',
            ),
          ],
          if (_error != null) ...[const SizedBox(height: 12), _ErrorLine(_error!)],
        ],
      );
}

class _ErrorLine extends StatelessWidget {
  final String message;
  const _ErrorLine(this.message);

  @override
  Widget build(BuildContext context) => CharakNoteBanner(
        icon: LucideIcons.circleAlert,
        message: message,
        tone: CharakStatusTone.declined,
      );
}

// ── One medicine ─────────────────────────────────────────────────────────────

/// The doctor's own words for each field. Only the name is required: not
/// every field applies to every medicine, and nothing is filled in for them.
class _MedicineForm extends StatefulWidget {
  final CharakMedicine? initial;
  const _MedicineForm({this.initial});

  @override
  State<_MedicineForm> createState() => _MedicineFormState();
}

class _MedicineFormState extends State<_MedicineForm> {
  late final Map<String, TextEditingController> _c;

  static const _fields = [
    ('medicine', 'Medicine', 'Paracetamol'),
    ('strength', 'Strength', '500 mg'),
    ('form', 'Form', 'Tablet, syrup…'),
    ('dose', 'Dose', '1 tablet'),
    ('frequency', 'Frequency', '1-0-1, every 8 hours, SOS'),
    ('duration', 'Duration', '5 days'),
    ('route', 'Route', 'Oral'),
    ('instructions', 'Instructions', 'After food'),
  ];

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    final values = {
      'medicine': m?.medicine, 'strength': m?.strength, 'form': m?.form, 'dose': m?.dose,
      'frequency': m?.frequency, 'duration': m?.duration, 'route': m?.route,
      'instructions': m?.instructions,
    };
    _c = {for (final (k, _, _) in _fields) k: TextEditingController(text: values[k] ?? '')};
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _v(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();

  // No keyboard padding here: CharakSheet rides up with the keyboard itself.
  @override
  Widget build(BuildContext context) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            for (final (k, label, hint) in _fields) ...[
              CharakField(
                label: label,
                placeholder: hint,
                controller: _c[k],
                autofocus: k == 'medicine' && widget.initial == null,
                textCapitalization: k == 'medicine' ? TextCapitalization.words : TextCapitalization.sentences,
                textInputAction: k == 'instructions' ? TextInputAction.done : TextInputAction.next,
                onChanged: k == 'medicine' ? (_) => setState(() {}) : null,
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            CharakButton(
              label: widget.initial == null ? 'Add' : 'Save',
              onPressed: _v('medicine') == null
                  ? null
                  : () => Navigator.pop(
                        context,
                        CharakMedicine(
                          medicine: _v('medicine')!, strength: _v('strength'), form: _v('form'),
                          dose: _v('dose'), frequency: _v('frequency'), duration: _v('duration'),
                          route: _v('route'), instructions: _v('instructions'),
                        ),
                      ),
            ),
          ]),
      );
}
