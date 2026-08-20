import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

final _categoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/categories') as List;
  return res.cast<Map<String, dynamic>>();
});

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl  = TextEditingController();
  String? _categoryId;
  File?   _photo;
  bool    _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (img != null) setState(() => _photo = File(img.path));
  }

  bool get _valid =>
      _nameCtrl.text.trim().length >= 2 && _categoryId != null && _photo != null;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      String? photoUrl;
      if (_photo != null) {
        final supabase = Supabase.instance.client;
        final bytes = await _photo!.readAsBytes();
        final ext   = _photo!.path.split('.').last;
        final path  = 'doctor-photos/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await supabase.storage.from('doctor-photos').uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: 'image/$ext'));
        photoUrl = supabase.storage.from('doctor-photos').getPublicUrl(path);
      }
      await ApiClient.instance.patch('/doctors/me', {
        'name': _nameCtrl.text.trim(),
        'category_id': _categoryId,
        'bio': _bioCtrl.text.trim(),
        if (photoUrl != null) 'photo_url': photoUrl,
      });
      if (mounted) context.go('/onboarding/verification');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(_categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your Profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CharakSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo picker
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: CharakColors.bgSubtle,
                    backgroundImage: _photo != null ? FileImage(_photo!) : null,
                    child: _photo == null
                        ? const Icon(Icons.add_a_photo, color: CharakColors.inkMuted, size: 28)
                        : null,
                  ),
                ),
              ),
              if (_photo == null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: CharakSpacing.sm),
                    child: Text('Add profile photo *',
                        style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                  ),
                ),
              const SizedBox(height: CharakSpacing.lg),

              // Name
              Text('Full name *', style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.xs),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(hintText: 'Dr. Anjali Sharma'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: CharakSpacing.base),

              // Specialty
              Text('Specialty *', style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.xs),
              cats.when(
                data: (list) => DropdownButtonFormField<String>(
                  value: _categoryId,
                  hint: const Text('Select specialty'),
                  decoration: const InputDecoration(),
                  items: list.map((c) => DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text(c['name'] as String),
                  )).toList(),
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Failed to load specialties', style: CharakText.caption.copyWith(color: CharakColors.danger)),
              ),
              const SizedBox(height: CharakSpacing.base),

              // Bio
              Text('Bio / Credentials', style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.xs),
              TextField(
                controller: _bioCtrl,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'MBBS, MD (Cardiology). 12 years of experience...'),
              ),
              const SizedBox(height: CharakSpacing.lg),

              if (_error != null)
                Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),

              CharakButton(
                label: 'Continue',
                onPressed: _valid ? _submit : null,
                isLoading: _loading,
              ),
              const SizedBox(height: CharakSpacing.base),
            ],
          ),
        ),
      ),
    );
  }
}
