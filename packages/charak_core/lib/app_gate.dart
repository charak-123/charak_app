import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'components/charak_button.dart';
import 'components/charak_controls.dart';
import 'design/tokens.dart';
import 'network/api_client.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// What `GET /config/app` says when this build is too old to keep using.
class CharakUpdateInfo {
  final String? minVersion;
  final String? storeUrl;
  const CharakUpdateInfo({this.minVersion, this.storeUrl});
}

/// The check every splash screen makes before routing anywhere.
///
/// When the API changes in a way an old build can't follow, ops raises
/// `min_app_version` (backend app_config). Builds below it get
/// [CharakUpdateRequiredScreen] instead of failing half way through a booking.
///
/// The check never blocks the app on its own failure: no network, a slow
/// server or an unreadable answer all mean "carry on". It waits at most
/// [timeout], so a cold start isn't held up by a slow request.
abstract final class CharakAppGate {
  static const timeout = Duration(seconds: 3);

  /// [app] is 'patient' or 'doctor'. Returns non-null only when an update is
  /// required.
  static Future<CharakUpdateInfo?> check(String app) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final platform = Platform.isIOS ? 'ios' : 'android';
      final query = Uri(queryParameters: {
        'app': app,
        'platform': platform,
        'version': info.version,
      }).query;
      final res = await ApiClient.instance.get('/config/app?$query').timeout(timeout);
      if (res is Map && res['update_required'] == true) {
        return CharakUpdateInfo(
          minVersion: res['min_version'] as String?,
          storeUrl: res['store_url'] as String?,
        );
      }
    } catch (_) {
      // Never lock someone out because the check itself failed.
    }
    return null;
  }
}

/// Full-screen, no way back: this build can't safely talk to the server any
/// more. Shown by the splash screen when [CharakAppGate.check] says so.
class CharakUpdateRequiredScreen extends StatelessWidget {
  final CharakUpdateInfo info;
  const CharakUpdateRequiredScreen({super.key, required this.info});

  Future<void> _openStore() async {
    final url = info.storeUrl;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = Platform.isIOS ? 'the App Store' : 'the Play Store';
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: CharakColors.ground,
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 34, 20, 24),
                child: CharakOutcomeState(
                  tone: CharakOutcomeTone.neutral,
                  icon: LucideIcons.circleArrowUp,
                  title: 'Update CHARAK',
                  message: info.storeUrl != null
                      ? 'This version is no longer supported. Update to keep booking '
                          'and paying safely. It only takes a moment.'
                      : 'This version is no longer supported. Update CHARAK from '
                          '$store to keep booking and paying safely.',
                ),
              ),
            ),
            if (info.storeUrl != null)
              CharakCtaBar(children: [
                Expanded(child: CharakButton(label: 'Update now', onPressed: _openStore)),
              ]),
          ]),
        ),
      ),
    );
  }
}
