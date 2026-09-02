import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:charak_core/charak_core.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../shared/charak_button.dart';

class IntakeScreen extends ConsumerStatefulWidget {
  final String doctorId;
  final Map<String, dynamic> extra;
  const IntakeScreen({super.key, required this.doctorId, required this.extra});
  @override
  ConsumerState<IntakeScreen> createState() => _State();
}

class _State extends ConsumerState<IntakeScreen> {
  final _textCtrl = TextEditingController();
  final _picker   = ImagePicker();
  final _recorder = AudioRecorder();

  List<File> _images = [];
  File? _voiceFile;
  String? _voiceTranscript;
  bool _recording  = false;
  bool _uploading  = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (x != null && mounted) setState(() => _images.add(File(x.path)));
  }

  Future<void> _takePhoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 75);
    if (x != null && mounted) setState(() => _images.add(File(x.path)));
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (path != null && mounted) {
        setState(() {
          _voiceFile      = File(path);
          _voiceTranscript = '[Voice note recorded — transcript pending]';
          _recording       = false;
        });
      }
    } else {
      final permitted = await _recorder.hasPermission();
      if (!permitted || !mounted) return;
      final dir  = await getTemporaryDirectory();
      final path = '${dir.path}/intake_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() => _recording = true);
    }
  }

  void _proceed() {
    context.push('/book/review', extra: {
      ...widget.extra,
      'doctor_id': widget.doctorId,
      'text': _textCtrl.text.trim(),
      'images': _images.map((f) => f.path).toList(),
      'voice_transcript': _voiceTranscript,
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CharakColors.bgSubtle,
    appBar: AppBar(
      title: const Text('Describe Your Issue'),
      backgroundColor: CharakColors.bg,
      foregroundColor: CharakColors.ink,
      elevation: 0,
    ),
    body: Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.all(CharakSpacing.base),
        children: [
          // Text input
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(CharakRadius.card),
              side: const BorderSide(color: CharakColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(CharakSpacing.base),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Describe your symptoms', style: CharakText.h2),
                const SizedBox(height: 8),
                TextField(
                  controller: _textCtrl,
                  maxLines: 5,
                  style: CharakText.body,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'e.g. I have had a fever for 2 days, headache, body aches...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 12),

          // Photos
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(CharakRadius.card),
              side: const BorderSide(color: CharakColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(CharakSpacing.base),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Photos (optional)', style: CharakText.h2),
                const SizedBox(height: 8),
                if (_images.isNotEmpty)
                  SizedBox(
                    height: 80,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _images.asMap().entries.map((e) => Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.all(CharakRadius.button),
                              child: Image.file(e.value, width: 80, height: 80, fit: BoxFit.cover),
                            ),
                          ),
                          Positioned(top: 0, right: 4, child: GestureDetector(
                            onTap: () => setState(() => _images.removeAt(e.key)),
                            child: Container(
                              decoration: const BoxDecoration(
                                  color: CharakColors.danger, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          )),
                        ],
                      )).toList(),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt_outlined, size: 16),
                    label: const Text('Camera'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(CharakRadius.button)),
                    ),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(CharakRadius.button)),
                    ),
                  )),
                ]),
              ]),
            ),
          ),

          const SizedBox(height: 12),

          // Voice recording
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(CharakRadius.card),
              side: const BorderSide(color: CharakColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(CharakSpacing.base),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Voice Note (optional)', style: CharakText.h2),
                const SizedBox(height: 8),
                if (_voiceTranscript != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: CharakColors.bgSubtle,
                      borderRadius: BorderRadius.all(CharakRadius.button),
                    ),
                    child: Text(_voiceTranscript!, style: CharakText.body),
                  ),
                  const SizedBox(height: 8),
                ],
                Center(
                  child: GestureDetector(
                    onTap: _toggleRecording,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: _recording ? CharakColors.danger : CharakColors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _recording ? Icons.stop : Icons.mic,
                        color: _recording ? Colors.white : CharakColors.primary,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    _recording ? 'Tap to stop recording' : 'Tap to record',
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                  ),
                ),
              ]),
            ),
          ),
        ],
      )),

      Container(
        padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 12, CharakSpacing.base, 24),
        color: CharakColors.bg,
        child: CharakButton(
          label: 'Review & Confirm',
          onPressed: (_textCtrl.text.trim().isNotEmpty || _images.isNotEmpty || _voiceFile != null)
              ? _proceed
              : null,
        ),
      ),
    ]),
  );
}
