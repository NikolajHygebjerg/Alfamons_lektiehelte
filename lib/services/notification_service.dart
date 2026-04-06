import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Lokale notifikationer til iPad – vises når appen er i baggrunden.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }
    // flutter_local_notifications er primært sat op til Android/iOS; Windows/Linux
    // udelades for at undgå runtime-fejl ved show/initialize.
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      _initialized = true;
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
    );
    const initSettings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final response = launchDetails!.notificationResponse;
      if (response?.payload != null && response!.payload!.isNotEmpty) {
        _onNotificationTapped(response);
      }
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    _initialized = true;
  }

  static void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    // Payload format: kidId|invitationId|challengerKidId
    final parts = payload.split('|');
    if (parts.length >= 3) {
      _pendingChallenge = (
        kidId: parts[0],
        invitationId: parts[1],
        challengerKidId: parts[2],
      );
    }
  }

  static ({String kidId, String invitationId, String challengerKidId})?
      _pendingChallenge;

  static ({String kidId, String invitationId, String challengerKidId})?
      takePendingChallenge() {
    final p = _pendingChallenge;
    _pendingChallenge = null;
    return p;
  }

  static ({String kidId, String invitationId, String challengerKidId})?
      peekPendingChallenge() {
    return _pendingChallenge;
  }

  static void clearPendingChallenge() {
    _pendingChallenge = null;
  }

  static Future<void> showChallengeNotification({
    required String kidId,
    required String invitationId,
    required String challengerKidId,
    required String challengerName,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();

    const android = AndroidNotificationDetails(
      'challenge',
      'Udfordringer',
      channelDescription: 'Notifikationer når du bliver udfordret',
      importance: Importance.high,
      priority: Priority.high,
    );

    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: android,
      iOS: darwin,
    );

    final payload = '$kidId|$invitationId|$challengerKidId';

    await _plugin.show(
      0,
      'Du er blevet udfordret!',
      '$challengerName vil kæmpe mod dig',
      details,
      payload: payload,
    );
  }

  static Future<void> showSimpleNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return;
    }
    if (!_initialized) await init();

    const android = AndroidNotificationDetails(
      'general',
      'Beskeder',
      channelDescription: 'Generelle spilbeskeder',
      importance: Importance.high,
      priority: Priority.high,
    );

    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: android,
      iOS: darwin,
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
    );
  }
}
