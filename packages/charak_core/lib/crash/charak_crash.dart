import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Crash and non-fatal error reporting (Firebase Crashlytics).
///
/// Call [CharakCrash.runGuarded] from `main()`, wrapping `runApp(...)`, before
/// anything else runs. That is the one place both halves of Flutter's error
/// surface can be caught: [FlutterError.onError] for errors raised during the
/// framework's own build/layout/paint work, and the zone's error handler for
/// everything outside it (a bad `Future`, a stray `Timer` callback). Missing
/// either one leaves a class of crash invisible in the dashboard.
///
/// Reporting is off in debug builds (`kDebugMode`) — a crash hit while
/// developing is not a user's crash, and debug builds would otherwise flood
/// the free-tier Crashlytics quota with noise from stepping through code.
class CharakCrash {
  CharakCrash._();

  /// True once [runGuarded] has set everything up. Call sites that want to
  /// record a handled (non-fatal) error check this first — recording before
  /// Firebase exists would itself throw.
  static bool _ready = false;

  static Future<void> runGuarded(Widget Function() buildApp) async {
    await runZonedGuarded<Future<void>>(() async {
      WidgetsFlutterBinding.ensureInitialized();

      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp();
        } catch (e) {
          // No google-services.json in this build (e.g. a CI check build with
          // no Firebase project wired up). Run without crash reporting rather
          // than fail to start.
          debugPrint('[crash] Firebase unavailable, reporting disabled: $e');
          runApp(buildApp());
          return;
        }
      }

      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);

      // Framework errors (build/layout/paint) — without this handler they
      // print to the console and are otherwise lost.
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      // Errors raised outside the Flutter framework's own error zone (e.g. a
      // platform channel callback). PlatformDispatcher is still inside the
      // zone runZonedGuarded establishes below, so both layers are covered.
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      _ready = true;
      runApp(buildApp());
    }, (error, stack) {
      // The zone's own handler: anything that escapes both of the above,
      // e.g. an error thrown from code that never touches Flutter at all.
      if (_ready) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      } else {
        debugPrint('[crash] uncaught before Crashlytics was ready: $error');
      }
    });
  }

  /// Records a handled error as non-fatal — a request that failed and was
  /// recovered from, not a crash. Safe to call even if [runGuarded] never
  /// ran (a plain `flutter test`, or a build with no Firebase project).
  static void recordError(Object error, StackTrace? stack, {String? reason}) {
    if (!_ready) return;
    FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
  }

  /// Tags crash reports with who hit them, without any health information —
  /// just the account id and role, the same scope the backend's own audit log
  /// uses. Call once after sign-in; call with `null` on sign-out so a crash
  /// report never carries a stale identity into the next session.
  static void setUser(String? userId) {
    if (!_ready) return;
    FirebaseCrashlytics.instance.setUserIdentifier(userId ?? '');
  }
}
