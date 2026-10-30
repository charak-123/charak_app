import 'package:flutter/widgets.dart';
import 'package:charak_core/charak_core.dart';

/// A kind of care patients browse on Home.
///
/// [category] is the backend's category name, which the directory filters on
/// and doctor registration matches by ("Nurse", "Pediatrics"); it stays as
/// it is. [name] is what patients read, everywhere a specialty is shown.
class Specialty {
  final String category;
  final String name;

  /// What it covers in plain words: patients look for a symptom more often
  /// than a specialty.
  final String hint;
  final IconData icon;

  /// Index into CharakTileTones.all.
  final int tone;

  const Specialty(this.category, this.name, this.hint, this.icon, this.tone);
}

const specialties = [
  Specialty('General Physician', 'General physician', 'Fever, cough, BP, sugar', LucideIcons.stethoscope, 0),
  Specialty('Pediatrics', 'Paediatrics', 'Babies & children', LucideIcons.baby, 1),
  Specialty('Cardiology', 'Cardiology', 'Heart & blood pressure', LucideIcons.heartPulse, 2),
  Specialty('Dermatology', 'Dermatology', 'Skin, hair & nails', LucideIcons.sparkles, 4),
  Specialty('Orthopedic', 'Orthopaedics', 'Bones, joints & back', LucideIcons.bone, 5),
  Specialty('Physiotherapy', 'Physiotherapy', 'Pain, injury & rehab', LucideIcons.personStanding, 3),
  Specialty('Gynecology', 'Gynaecology', "Women's health", LucideIcons.flower2, 2),
  Specialty('Nurse', 'Nursing', 'Injections & dressings', LucideIcons.syringe, 0),
];

/// The patient-facing name for a backend category name: "Nurse" reads
/// "Nursing". A category not in [specialties] is shown as it is.
String specialtyName(String? category) {
  if (category == null) return '';
  final key = category.trim().toLowerCase();
  for (final s in specialties) {
    if (s.category.toLowerCase() == key) return s.name;
  }
  return category;
}
