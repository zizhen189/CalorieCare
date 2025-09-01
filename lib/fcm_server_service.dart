import 'package:http/http.dart' as http;
import 'dart:convert';

/// 这个类用于与FCM服务端API通信
/// 注意：由于Flutter中处理RSA签名比较复杂，
/// 这里提供了一个简化的实现。在生产环境中，
/// 建议使用后端服务来处理FCM推送。
class FCMServerService {
  static const String _projectId = 'caloriecare-164c4';
  static const String _fcmEndpoint = 'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send';

  /// 使用服务器密钥发送FCM通知（简化版本）
  /// 注意：这个方法需要有效的服务器访问令牌
  static Future<bool> sendNotification({
    required String fcmToken,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? accessToken,
  }) async {
    try {
      if (accessToken == null) {
        print('Warning: No access token provided for FCM request');
        return false;
      }

      final message = {
        'message': {
          'token': fcmToken,
          'notification': {
            'title': title,
            'body': body,
          },
          'data': data ?? {},
          'android': {
            'notification': {
              'channel_id': 'caloriecare_default_channel',
              'priority': 'high',
              'default_sound': true,
              'default_vibrate_timings': true,
            },
            'priority': 'high',
          },
          'apns': {
            'headers': {
              'apns-priority': '10',
            },
            'payload': {
              'aps': {
                'alert': {
                  'title': title,
                  'body': body,
                },
                'sound': 'default',
                'badge': 1,
              },
            },
          },
        },
      };

      final response = await http.post(
        Uri.parse(_fcmEndpoint),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(message),
      );

      if (response.statusCode == 200) {
        print('FCM notification sent successfully');
        return true;
      } else {
        print('Failed to send FCM notification: ${response.statusCode}');
        print('Response body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error sending FCM notification: $e');
      return false;
    }
  }

  /// 批量发送通知给多个设备
  static Future<Map<String, bool>> sendBatchNotifications({
    required Map<String, String> deviceTokens, // userId -> fcmToken
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? accessToken,
  }) async {
    final results = <String, bool>{};
    
    for (final entry in deviceTokens.entries) {
      final userId = entry.key;
      final fcmToken = entry.value;
      
      final success = await sendNotification(
        fcmToken: fcmToken,
        title: title,
        body: body,
        data: data,
        accessToken: accessToken,
      );
      
      results[userId] = success;
      
      // 添加小延迟以避免速率限制
      await Future.delayed(Duration(milliseconds: 100));
    }
    
    return results;
  }
}

/// FCM推送通知的模板类
class FCMNotificationTemplate {
  static Map<String, dynamic> createInvitationData({
    required String inviterId,
    required String inviterName,
    required String supervisionId,
  }) {
    return {
      'type': 'supervisor_invitation',
      'inviterId': inviterId,
      'inviterName': inviterName,
      'supervisionId': supervisionId,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  static Map<String, dynamic> createCustomMessageData({
    required String senderId,
    required String senderName,
    required String message,
  }) {
    return {
      'type': 'custom_message',
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  static Map<String, dynamic> createCalorieAdjustmentData({
    required Map<String, dynamic> adjustmentData,
  }) {
    return {
      'type': 'calorie_adjustment',
      'adjustmentData': jsonEncode(adjustmentData),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
