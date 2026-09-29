// Builds the map links for a home visit.
//
// Kept out of the screen so the choice between a dropped pin, a text address
// and "not released yet" can be tested. Getting it wrong sends a doctor to the
// wrong house, which is not something a widget test would notice.

/// The `geo:` link to hand the phone's maps app, or null when the booking has
/// no usable location.
///
/// Coordinates win over the text address: a home visit is often to a place a
/// geocoder gets wrong, and the pin the patient dropped is the one that is
/// actually right.
Uri? patientMapUri(Map<String, dynamic> booking) {
  final lat = (booking['patient_address_lat'] as num?)?.toDouble();
  final lng = (booking['patient_address_lng'] as num?)?.toDouble();
  final address = (booking['patient_address'] as String?)?.trim();

  if (lat != null && lng != null) {
    final label = Uri.encodeComponent(
      (address != null && address.isNotEmpty) ? address : 'Patient',
    );
    return Uri.parse('geo:$lat,$lng?q=$lat,$lng($label)');
  }
  if (address != null && address.isNotEmpty) {
    return Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}');
  }
  // Withheld until the doctor accepts, or an online consult.
  return null;
}

/// The browser fallback, for a phone with no app registered for `geo:`.
Uri? patientMapWebUri(Map<String, dynamic> booking) {
  final lat = (booking['patient_address_lat'] as num?)?.toDouble();
  final lng = (booking['patient_address_lng'] as num?)?.toDouble();
  final address = (booking['patient_address'] as String?)?.trim();

  final String query;
  if (lat != null && lng != null) {
    query = '$lat,$lng';
  } else if (address != null && address.isNotEmpty) {
    query = Uri.encodeComponent(address);
  } else {
    return null;
  }
  return Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
}
