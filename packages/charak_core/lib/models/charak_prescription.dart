/// A prescription as the backend sends it (backend services/prescriptions.py
/// `public()`): the structured record, its medicines and its follow-up.
///
/// The doctor writes it as a draft, sends it once, and corrects it with a new
/// version. The patient opens it with `POST /prescriptions/{id}/view`, which
/// records the first open and completes the booking.
class CharakPrescription {
  final String id;
  final String bookingId;
  final int version;

  /// `prescription`, or `notes` when nothing needed prescribing.
  final String kind;

  /// `draft`, `submitted` or `superseded`.
  final String status;
  final int? patientAge;
  final String? patientSex;
  final String? complaints;
  final String? diagnosis;
  final String? investigations;
  final String? advice;
  final bool tpgAttested;
  final bool hasUpload;
  final bool hasPdf;
  final DateTime? submittedAt;
  final DateTime? firstViewedAt;
  final String? supersedesId;

  /// Set on a superseded version opened from an old link: the current one.
  final String? replacedById;
  final List<CharakMedicine> items;
  final CharakFollowUp? followUp;

  const CharakPrescription({
    required this.id,
    required this.bookingId,
    this.version = 1,
    this.kind = 'prescription',
    this.status = 'draft',
    this.patientAge,
    this.patientSex,
    this.complaints,
    this.diagnosis,
    this.investigations,
    this.advice,
    this.tpgAttested = false,
    this.hasUpload = false,
    this.hasPdf = false,
    this.submittedAt,
    this.firstViewedAt,
    this.supersedesId,
    this.replacedById,
    this.items = const [],
    this.followUp,
  });

  bool get isNotes => kind == 'notes';
  bool get isDraft => status == 'draft';
  bool get isSent => status == 'submitted';
  bool get isSuperseded => status == 'superseded';
  bool get isCorrection => supersedesId != null;

  factory CharakPrescription.fromJson(Map<String, dynamic> j) => CharakPrescription(
        id: j['id'] as String,
        bookingId: j['booking_id'] as String? ?? '',
        version: (j['version'] as num?)?.toInt() ?? 1,
        kind: j['kind'] as String? ?? 'prescription',
        status: j['status'] as String? ?? 'draft',
        patientAge: (j['patient_age'] as num?)?.toInt(),
        patientSex: j['patient_sex'] as String?,
        complaints: _text(j['complaints']),
        diagnosis: _text(j['diagnosis']),
        investigations: _text(j['investigations']),
        advice: _text(j['advice']),
        tpgAttested: j['tpg_attested'] as bool? ?? false,
        hasUpload: j['has_upload'] as bool? ?? false,
        hasPdf: j['has_pdf'] as bool? ?? false,
        submittedAt: _time(j['submitted_at']),
        firstViewedAt: _time(j['first_viewed_at']),
        supersedesId: j['supersedes_id'] as String?,
        replacedById: j['replaced_by_id'] as String?,
        items: (j['items'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => CharakMedicine.fromJson(m.cast<String, dynamic>()))
            .toList(),
        followUp: j['follow_up'] is Map
            ? CharakFollowUp.fromJson((j['follow_up'] as Map).cast<String, dynamic>())
            : null,
      );
}

/// One medicine line. Only the name is required: not every field applies to
/// every medicine (spec §9.2), and nothing here is filled in for the doctor.
class CharakMedicine {
  final String medicine;
  final String? strength;
  final String? form;
  final String? dose;
  final String? route;
  final String? frequency;
  final String? duration;
  final String? instructions;

  const CharakMedicine({
    required this.medicine,
    this.strength,
    this.form,
    this.dose,
    this.route,
    this.frequency,
    this.duration,
    this.instructions,
  });

  factory CharakMedicine.fromJson(Map<String, dynamic> j) => CharakMedicine(
        medicine: j['medicine'] as String? ?? '',
        strength: _text(j['strength']),
        form: _text(j['form']),
        dose: _text(j['dose']),
        route: _text(j['route']),
        frequency: _text(j['frequency']),
        duration: _text(j['duration']),
        instructions: _text(j['instructions']),
      );

  Map<String, dynamic> toJson() => {
        'medicine': medicine.trim(),
        'strength': strength,
        'form': form,
        'dose': dose,
        'route': route,
        'frequency': frequency,
        'duration': duration,
        'instructions': instructions,
      };

  /// "Paracetamol 500 mg"
  String get title => [medicine, strength].whereType<String>().join(' ');

  /// "1 tablet · 1-0-1 · 5 days", the parts the doctor filled in.
  String get schedule =>
      [dose, frequency, duration].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  /// "Tablet · Oral"
  String get formRoute => [form, route].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
}

/// The doctor's follow-up recommendation. Nothing is booked or charged from
/// it: it's a recommendation with a reminder and a Book button.
class CharakFollowUp {
  final String? id;
  final DateTime date;

  /// `online_consult`, `home_visit` or `either`.
  final String channel;
  final String? note;
  final String status;

  const CharakFollowUp({
    this.id,
    required this.date,
    required this.channel,
    this.note,
    this.status = 'open',
  });

  factory CharakFollowUp.fromJson(Map<String, dynamic> j) => CharakFollowUp(
        id: j['id'] as String?,
        date: DateTime.parse(j['recommended_date'] as String),
        channel: j['channel'] as String? ?? 'either',
        note: _text(j['note']),
        status: j['status'] as String? ?? 'open',
      );

  /// What the submit endpoint takes.
  Map<String, dynamic> toSubmitJson() => {
        'date': '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'channel': channel,
        'note': note,
      };

  String get channelLabel => switch (channel) {
        'online_consult' => 'Online consultation',
        'home_visit' => 'Home visit',
        _ => 'Online consultation or home visit',
      };
}

String? _text(Object? v) {
  final s = (v as String?)?.trim();
  return (s == null || s.isEmpty) ? null : s;
}

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
