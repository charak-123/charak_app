import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:charak_core/charak_core.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

enum _IntakeType { text, voice, photo, video }

class IntakeScreen extends ConsumerStatefulWidget {
  final String doctorId;
  final Map<String, dynamic> extra;
  const IntakeScreen({super.key, required this.doctorId, required this.extra});
  @override
  ConsumerState<IntakeScreen> createState() => _State();
}

class _State extends ConsumerState<IntakeScreen> {
  _IntakeType _type = _IntakeType.text;

  final _textCtrl = TextEditingController();
  final _picker   = ImagePicker();
  final _recorder = AudioRecorder();

  final List<File> _images = [];
  final List<File> _videos = [];
  File? _voiceFile;
  String? _voiceTranscript;
  final _transcriptCtrl = TextEditingController();
  bool _recording  = false;

  // Drives the "Recording… 0:12" readout only; the recorder owns the audio.
  Timer? _tick;
  int _elapsed = 0;

  @override
  void dispose() {
    _textCtrl.dispose();
    _transcriptCtrl.dispose();
    _tick?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_type) {
    _IntakeType.text  => _textCtrl.text.trim().isNotEmpty,
    _IntakeType.voice => _voiceFile != null,
    _IntakeType.photo => _images.isNotEmpty,
    _IntakeType.video => _videos.isNotEmpty,
  };

  /// Backend caps (see storage.LIMITS): 10MB per intake image, 50MB per video.
  /// Both are enforced *after* the upload finishes, so anything oversized costs
  /// the patient a full upload on mobile data before being refused. These
  /// limits keep that from happening in the first place.
  static const _maxRecordingSeconds = 180;
  static const _maxImageBytes = 10 * 1024 * 1024;
  static const _maxVideoBytes = 50 * 1024 * 1024;

  Future<void> _pickImage() async {
    // A modern phone camera shoots 4000px+; a doctor looking at a rash or a
    // wound gains nothing past 1600px, and the difference is megabytes on a
    // connection that may be metered.
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 70,
    );
    if (x == null || !mounted) return;
    final file = File(x.path);
    if (!await _withinLimit(file, _maxImageBytes, 'photo')) return;
    if (mounted) setState(() => _images.add(file));
  }

  Future<void> _pickVideo() async {
    // Unbounded 1080p passes 50MB in well under a minute. Forty-five seconds
    // is more than enough to show a symptom, and keeps the clip uploadable.
    final x = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 45),
    );
    if (x == null || !mounted) return;
    final file = File(x.path);
    if (!await _withinLimit(file, _maxVideoBytes, 'video')) return;
    if (mounted) setState(() => _videos.add(file));
  }

  /// Rejects an oversized attachment here rather than after the upload.
  Future<bool> _withinLimit(File f, int maxBytes, String label) async {
    final size = await f.length();
    if (size <= maxBytes) return true;
    if (mounted) {
      showCharakToast(context,
          message: 'That $label is '
              '${(size / (1024 * 1024)).toStringAsFixed(1)}MB — the limit is '
              '${maxBytes ~/ (1024 * 1024)}MB.');
    }
    return false;
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      _tick?.cancel();
      if (path != null && mounted) {
        setState(() {
          _voiceFile = File(path);
          _recording = false;
        });
      }
    } else {
      final permitted = await _recorder.hasPermission();
      if (!permitted || !mounted) return;
      final dir  = await getTemporaryDirectory();
      final path = '${dir.path}/intake_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      _elapsed = 0;
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed++);
        // Stop at the cap rather than letting the recording run: every second
        // is upload bytes on a metered connection and billable audio at the
        // transcription step. Three minutes is far longer than anyone needs to
        // describe a complaint.
        if (_elapsed >= _maxRecordingSeconds) {
          _toggleRecording();
          showCharakToast(context,
              message: 'Recording stopped at three minutes — that is the limit '
                  'for a voice note.');
        }
      });
      setState(() => _recording = true);
    }
  }

  void _proceed() {
    context.push('/book/review', extra: {
      ...widget.extra,
      'doctor_id': widget.doctorId,
      'text': _textCtrl.text.trim(),
      'images': _images.map((f) => f.path).toList(),
      'videos': _videos.map((f) => f.path).toList(),
      'voice_path': _voiceFile?.path,
      'voice_transcript': _voiceTranscript,
    });
  }

  String get _clock =>
      '${_elapsed ~/ 60}:${(_elapsed % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CharakColors.ground,
    appBar: const CharakTopBar(title: 'Describe the issue'),
    body: Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text('Share as much as you like — the doctor reads it directly.',
              style: charakScreenSubStyle),
          const SizedBox(height: 14),

          CharakSegmented<_IntakeType>(
            value: _type,
            onChanged: (t) => setState(() => _type = t),
            segments: const [
              CharakSegment(value: _IntakeType.text,  label: 'Text',  icon: Icons.notes_rounded),
              CharakSegment(value: _IntakeType.voice, label: 'Voice', icon: Icons.mic_none_rounded),
              CharakSegment(value: _IntakeType.photo, label: 'Photo', icon: Icons.photo_camera_outlined),
              CharakSegment(value: _IntakeType.video, label: 'Video', icon: Icons.videocam_outlined),
            ],
          ),

          // ── Text — `.intake-box` ───────────────────────────────────────
          if (_type == _IntakeType.text) ...[
            const SizedBox(height: 12),
            SizedBox(
              // `.intake-box textarea { min-height: 120px }`
              child: CharakField(
                controller: _textCtrl,
                placeholder: 'e.g. Fever since yesterday evening, mild body '
                    'ache, taking Crocin…',
                maxLines: null,
                minLines: 5,
                hint: "Doctors prefer specifics: how long, how severe, "
                    "anything you've tried.",
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],

          // ── Voice — `.mic-box` + `.transcript` ─────────────────────────
          if (_type == _IntakeType.voice) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
        color: CharakColors.card,
                borderRadius: const BorderRadius.all(CharakRadius.card),
              ),
              child: Column(children: [
                if (_recording) ...[
                  const CharakMicWave(),
                  const SizedBox(height: 12),
                  _MicButton(recording: true, onTap: _toggleRecording),
                  const SizedBox(height: 12),
                  Text('Recording… $_clock · tap to stop',
                      style: CharakText.caption.copyWith(
                        color: CharakColors.inkMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ] else ...[
                  _MicButton(recording: false, onTap: _toggleRecording),
                  const SizedBox(height: 12),
                  Text('Tap to describe your issue by voice',
                      style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                ],
              ]),
            ),
            if (_voiceFile != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: CharakColors.bgSubtle,
                  borderRadius: const BorderRadius.all(CharakRadius.card),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // `.transcript b` — 11px/600 uppercase success label.
                  Text('TRANSCRIBED · EDITABLE',
                      style: CharakText.micro.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 11 * 0.05,
                        color: CharakColors.success,
                      )),
                  const SizedBox(height: 5),
                  Text(
                    'Your doctor will get this recording, transcribed and '
                    'summarised. Add anything else in your own words below.',
                    style: CharakText.caption
                        .copyWith(color: CharakColors.inkMuted),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _transcriptCtrl,
                    maxLines: null,
                    cursorColor: CharakColors.primary,
                    style: CharakText.body.copyWith(fontSize: 13.5, height: 1.6),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Optional — anything to add?',
                      hintStyle: CharakText.body.copyWith(
                          fontSize: 13.5, color: CharakColors.inkMuted),
                    ),
                    onChanged: (v) =>
                        _voiceTranscript = v.trim().isEmpty ? null : v,
                  ),
                ]),
              ),
            ],
          ],

          // ── Photo — `.attach-row` ──────────────────────────────────────
          if (_type == _IntakeType.photo) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              ..._images.map((f) => _AttachTile(
                attached: true,
                onTap: () => setState(() => _images.remove(f)),
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(CharakRadius.button),
                  child: Image.file(f, width: 76, height: 76, fit: BoxFit.cover),
                ),
              )),
              _AttachTile(
                onTap: _pickImage,
                child: Icon(Icons.add, size: 22, color: CharakColors.inkMuted),
              ),
            ]),
            const SizedBox(height: 10),
            Text('Rashes, wounds, reports — anything visual helps.',
                style: charakHintStyle),
          ],

          // ── Video — `.attach-row` ──────────────────────────────────────
          if (_type == _IntakeType.video) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              ..._videos.map((f) => _AttachTile(
                attached: true,
                onTap: () => setState(() => _videos.remove(f)),
                child: Icon(Icons.videocam,
                    size: 22, color: CharakColors.primaryDeep),
              )),
              _AttachTile(
                onTap: _pickVideo,
                child: Icon(Icons.add, size: 22, color: CharakColors.inkMuted),
              ),
            ]),
            const SizedBox(height: 10),
            Text('Show how you move or the affected area. Max 2 minutes.',
                style: charakHintStyle),
          ],

          // ── `.reassure` ────────────────────────────────────────────────
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.verified_user_outlined,
                  size: 15, color: CharakColors.success),
            ),
            const SizedBox(width: 8),
            Expanded(
              // States the real boundary. The previous line promised nothing
              // was "analyzed by AI", which stopped being true when voice
              // notes began going to Gemini for transcription and summary —
              // a claim the store listing and privacy policy have to match.
              child: Text('Your doctor reads this directly. AI only transcribes '
                  'and summarises your voice note — your photos and video are '
                  'never analysed.',
                  style: charakHintStyle),
            ),
          ]),
        ],
      )),

      CharakCtaBar.single(
        CharakButton(
          label: 'Continue',
          onPressed: _canContinue ? _proceed : null,
        ),
      ),
    ]),
  );
}

/// `.mic-btn` — 62px circle, primary while idle and danger (a stop square)
/// while recording.
class _MicButton extends StatelessWidget {
  final bool recording;
  final VoidCallback onTap;
  const _MicButton({required this.recording, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: CharakDurations.buttonPress,
      width: 62, height: 62,
      decoration: BoxDecoration(
        color: recording ? CharakColors.danger : CharakColors.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded,
          color: CharakColors.onPrimary, size: 24),
    ),
  );
}

/// `.attach-tile` — 76×76 dashed drop target; once a file is attached the
/// border goes solid, the fill turns `primarySoft`, and a success tick pins
/// to the top-right corner.
class _AttachTile extends StatelessWidget {
  final Widget child;
  final bool attached;
  final VoidCallback onTap;
  const _AttachTile({required this.child, required this.onTap, this.attached = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      width: 76,
      height: 76,
      child: Stack(clipBehavior: Clip.none, children: [
        CustomPaint(
          // 1px stroke here, unlike the 1.5px `.upload-tile`.
          painter: CharakDashedBorderPainter(
            color: CharakColors.border,
            dashed: !attached,
            radius: 10,
            strokeWidth: 1,
          ),
          child: Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: attached ? CharakColors.primarySoft : CharakColors.bgSubtle,
              borderRadius: const BorderRadius.all(CharakRadius.button),
            ),
            child: child,
          ),
        ),
        if (attached)
          Positioned(
            top: -6, right: -6,
            child: Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                  color: CharakColors.success, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(Icons.check, size: 11, color: CharakColors.onPrimary),
            ),
          ),
      ]),
    ),
  );
}
