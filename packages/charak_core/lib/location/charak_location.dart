import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Why a location fix could not be taken. [message] is safe to show as-is.
class CharakLocationException implements Exception {
  final String message;
  const CharakLocationException(this.message);
  @override
  String toString() => message;
}

/// A device fix plus, when the phone's geocoder could read it, the street
/// address it falls on. Every address field is optional: reverse geocoding
/// needs a network and a geocoder on the device, so callers must work with the
/// coordinates alone.
class CharakPlace {
  final double lat;
  final double lng;
  final String? line1;
  final String? line2;
  final String? city;
  final String? pincode;

  const CharakPlace({
    required this.lat,
    required this.lng,
    this.line1,
    this.line2,
    this.city,
    this.pincode,
  });

  bool get hasAddress => [line1, line2, city, pincode].any((s) => s != null);
}

class CharakLocation {
  CharakLocation._();

  /// Take a device fix and look up the address at it.
  ///
  /// Throws [CharakLocationException] if no fix can be taken. A failed address
  /// lookup is not an error: the fix is still returned, without address text.
  static Future<CharakPlace> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const CharakLocationException(
          'Location is turned off on this phone. Turn it on to pin the address.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      throw const CharakLocationException(
          'Location permission is blocked for Charak. Enable it in Settings '
          'to pin this address.');
    }
    if (perm == LocationPermission.denied) {
      throw const CharakLocationException(
          'Location permission is needed to pin the address.');
    }

    final Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
    } catch (_) {
      throw const CharakLocationException(
          "Couldn't get a location fix. Move somewhere with a clearer signal "
          'and try again.');
    }

    try {
      final marks = await Geocoding().placemarkFromCoordinates(pos.latitude, pos.longitude)
          .timeout(const Duration(seconds: 8));
      if (marks.isNotEmpty) return _fromPlacemark(pos, marks.first);
    } catch (_) {
      // No geocoder, no network or a timeout: keep the fix.
    }
    return CharakPlace(lat: pos.latitude, lng: pos.longitude);
  }

  static CharakPlace _fromPlacemark(Position pos, Placemark m) {
    String? clean(String? s) {
      final t = s?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    // `name` is often just the house number or a Plus Code, so build the first
    // line from the number/name plus the street rather than trusting either.
    final name = clean(m.name);
    final street = clean(m.thoroughfare) ?? clean(m.street);
    final isPlusCode =
        name != null && RegExp(r'^[0-9A-Z]{4}\+[0-9A-Z]{2,}').hasMatch(name);
    final line1 = [
      if (name != null && !isPlusCode && name != street) name,
      if (street != null) street,
    ].join(', ');

    final pin = m.postalCode ?? '';
    return CharakPlace(
      lat: pos.latitude,
      lng: pos.longitude,
      line1: line1.isEmpty ? null : line1,
      line2: clean(m.subLocality),
      city: clean(m.locality) ?? clean(m.subAdministrativeArea),
      pincode: RegExp(r'^\d{6}$').hasMatch(pin) ? pin : null,
    );
  }
}
