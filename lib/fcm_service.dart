import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  String? _currentUserId;
  String? _fcmToken;
  String? _accessToken;
  DateTime? _tokenExpiry;

  /// 初始化FCM服务
  Future<void> initialize(String userId) async {
    print('=== Initializing FCM Service ===');
    _currentUserId = userId;
    
    try {
      // 请求通知权限
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      
      print('FCM permission status: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // 获取FCM令牌
        _fcmToken = await _firebaseMessaging.getToken();
        print('FCM Token: $_fcmToken');
        
        if (_fcmToken != null) {
          // 保存令牌到Firebase
          await _saveFCMToken(_fcmToken!, userId);
        }
        
        // 设置前台消息处理
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        
        // 设置背景消息处理
        FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);
        
        // 检查应用启动时的通知
        RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
        if (initialMessage != null) {
          _handleBackgroundMessage(initialMessage);
        }
        
        // 令牌刷新监听
        _firebaseMessaging.onTokenRefresh.listen((token) {
          print('FCM Token refreshed: $token');
          _fcmToken = token;
          if (_currentUserId != null) {
            _saveFCMToken(token, _currentUserId!);
          }
        });
        
        // 初始化本地通知
        await _initializeLocalNotifications();
        
        print('FCM Service initialized successfully');
      } else {
        print('FCM permission denied');
      }
    } catch (e) {
      print('Error initializing FCM service: $e');
    }
  }

  /// 初始化本地通知
  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    
    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    
    // 创建通知渠道
    await _createNotificationChannels();
  }

  /// 创建通知渠道
  Future<void> _createNotificationChannels() async {
    // 邀请通知渠道
    const AndroidNotificationChannel invitationChannel = AndroidNotificationChannel(
      'supervisor_invitations_channel',
      'Supervisor Invitations',
      description: 'Notifications for supervisor invitations',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    
    // 自定义消息渠道
    const AndroidNotificationChannel messageChannel = AndroidNotificationChannel(
      'custom_messages_channel',
      'Custom Messages',
      description: 'Notifications for custom messages from supervisors',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    
    // 卡路里调整渠道
    const AndroidNotificationChannel calorieChannel = AndroidNotificationChannel(
      'calorie_adjustment_channel',
      'Calorie Adjustment Notifications',
      description: 'Notifications for calorie target adjustments',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    
    // 默认渠道
    const AndroidNotificationChannel defaultChannel = AndroidNotificationChannel(
      'caloriecare_default_channel',
      'CalorieCare Notifications',
      description: 'Default notifications for CalorieCare app',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    
    // 注册渠道
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(invitationChannel);
    
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(messageChannel);
    
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(calorieChannel);
    
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(defaultChannel);
  }

  /// 保存FCM令牌到Firebase
  Future<void> _saveFCMToken(String token, String userId) async {
    try {
      await _database.child('device_tokens/$userId').set({
        'fcm_token': token,
        'platform': Platform.operatingSystem,
        'timestamp': DateTime.now().toIso8601String(),
        'app_version': '1.0.0',
      });
      print('FCM token saved for user: $userId');
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  /// 获取Firebase Admin SDK访问令牌
  /// 注意：由于Flutter中处理RSA签名复杂，这里返回null
  /// 在实际生产环境中，建议使用后端服务来处理FCM推送
  Future<String?> _getAccessToken() async {
    print('Access token generation requires backend service');
    print('For production use, implement server-side FCM sending');
    return null; // 暂时返回null，实际推送会回退到RTDB方式
  }

  /// 发送FCM推送通知
  Future<bool> sendPushNotification({
    required String targetUserId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? channelId,
  }) async {
    try {
      // 获取目标用户的FCM令牌
      final tokenSnapshot = await _database.child('device_tokens/$targetUserId').get();
      if (!tokenSnapshot.exists) {
        print('No FCM token found for user: $targetUserId');
        return false;
      }
      
      final tokenData = tokenSnapshot.value as Map<dynamic, dynamic>;
      final fcmToken = tokenData['fcm_token'] as String?;
      
      if (fcmToken == null) {
        print('FCM token is null for user: $targetUserId');
        return false;
      }
      
      // 获取访问令牌
      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        print('Failed to get access token');
        return false;
      }
      
      // 构建FCM消息
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
              'channel_id': channelId ?? 'caloriecare_default_channel',
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
      
      // 发送FCM请求
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/caloriecare-164c4/messages:send'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(message),
      );
      
      if (response.statusCode == 200) {
        print('FCM notification sent successfully to user: $targetUserId');
        return true;
      } else {
        print('Failed to send FCM notification: ${response.statusCode} - ${response.body}');
        
        // 检查是否是无效令牌
        if (response.statusCode == 404 && response.body.contains('UNREGISTERED')) {
          await _removeInvalidToken(targetUserId);
        }
        return false;
      }
    } catch (e) {
      print('Error sending FCM notification: $e');
      return false;
    }
  }

  /// 移除无效的FCM令牌
  Future<void> _removeInvalidToken(String userId) async {
    try {
      await _database.child('device_tokens/$userId').remove();
      print('Removed invalid FCM token for user: $userId');
    } catch (e) {
      print('Error removing invalid token: $e');
    }
  }

  /// 处理前台消息
  void _handleForegroundMessage(RemoteMessage message) {
    print('=== Foreground Message Received ===');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');
    print('Data: ${message.data}');
    
    // 显示本地通知
    _showLocalNotification(message);
  }

  /// 处理背景消息
  void _handleBackgroundMessage(RemoteMessage message) {
    print('=== Background Message Received ===');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');
    print('Data: ${message.data}');
    
    // 这里可以根据数据执行相应的操作
    // 例如导航到特定页面、更新UI等
  }

  /// 显示本地通知
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'caloriecare_default_channel',
      'CalorieCare Notifications',
      channelDescription: 'Default notifications for CalorieCare app',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  /// 通知点击处理
  void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        print('Notification data: $data');
        
        // 根据通知类型执行相应操作
        // 这里可以添加导航逻辑
      } catch (e) {
        print('Error parsing notification payload: $e');
      }
    }
  }

  /// 发送邀请通知
  Future<bool> sendInvitationNotification({
    required String receiverId,
    required String inviterId,
    required String inviterName,
    required String supervisionId,
  }) async {
    return await sendPushNotification(
      targetUserId: receiverId,
      title: 'Supervisor Invitation',
      body: '$inviterName invites you to become mutual supervisors',
      data: {
        'type': 'supervisor_invitation',
        'inviterId': inviterId,
        'inviterName': inviterName,
        'supervisionId': supervisionId,
        'timestamp': DateTime.now().toIso8601String(),
      },
      channelId: 'supervisor_invitations_channel',
    );
  }

  /// 发送自定义消息通知
  Future<bool> sendCustomMessage({
    required String receiverId,
    required String senderId,
    required String senderName,
    required String message,
  }) async {
    return await sendPushNotification(
      targetUserId: receiverId,
      title: 'New Message from $senderName',
      body: message,
      data: {
        'type': 'custom_message',
        'senderId': senderId,
        'senderName': senderName,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
      },
      channelId: 'custom_messages_channel',
    );
  }

  /// 发送卡路里调整通知
  Future<bool> sendCalorieAdjustmentNotification({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> adjustmentData,
  }) async {
    return await sendPushNotification(
      targetUserId: userId,
      title: title,
      body: body,
      data: {
        'type': 'calorie_adjustment',
        'adjustmentData': jsonEncode(adjustmentData),
        'timestamp': DateTime.now().toIso8601String(),
      },
      channelId: 'calorie_adjustment_channel',
    );
  }

  /// 获取当前FCM令牌
  String? get currentToken => _fcmToken;

  /// 获取当前用户ID
  String? get currentUserId => _currentUserId;

  /// 清理资源
  void dispose() {
    _currentUserId = null;
    _fcmToken = null;
    _accessToken = null;
    _tokenExpiry = null;
  }
}

/// 处理背景消息的顶级函数
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('=== Background Message Handler ===');
  print('Title: ${message.notification?.title}');
  print('Body: ${message.notification?.body}');
  print('Data: ${message.data}');
  
  // 这里可以执行一些后台任务
  // 注意：不要在这里执行UI操作
}
