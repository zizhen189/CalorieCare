import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:caloriecare/session_service.dart';
import 'package:caloriecare/user_model.dart';
import 'dart:async';

/// 全局通知管理器
/// 负责管理所有类型的通知监听器和显示
/// 确保在应用的整个生命周期中都能正常接收通知
class GlobalNotificationManager {
  static final GlobalNotificationManager _instance = GlobalNotificationManager._internal();
  factory GlobalNotificationManager() => _instance;
  GlobalNotificationManager._internal();

  // 核心服务
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // 监听器管理
  StreamSubscription<DatabaseEvent>? _invitationListener;
  StreamSubscription<DatabaseEvent>? _customMessageListener;
  StreamSubscription<RemoteMessage>? _fcmForegroundListener;
  StreamSubscription<RemoteMessage>? _fcmBackgroundListener;

  // 状态管理
  String? _currentUserId;
  bool _isInitialized = false;
  bool _listenersActive = false;

  // 回调管理
  Function(String, Map<String, dynamic>)? _onInvitationReceived;
  Function(RemoteMessage)? _onMessageReceived;
  
  // 去重管理
  final Set<String> _processedNotifications = <String>{};
  Timer? _cleanupTimer;

  /// 初始化全局通知管理器
  Future<void> initialize() async {
    if (_isInitialized) {
      print('GlobalNotificationManager already initialized');
      return;
    }

    print('=== Initializing Global Notification Manager ===');
    
    try {
      // 初始化本地通知
      await _initializeLocalNotifications();
      
      // 初始化FCM
      await _initializeFCM();
      
      _isInitialized = true;
      print('Global Notification Manager initialized successfully');
    } catch (e) {
      print('Error initializing Global Notification Manager: $e');
    }
  }

  /// 初始化本地通知
  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    
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
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

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
    
    // 默认渠道
    const AndroidNotificationChannel defaultChannel = AndroidNotificationChannel(
      'caloriecare_default_channel',
      'CalorieCare Notifications',
      description: 'Default notifications for CalorieCare app',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    
    await androidPlugin.createNotificationChannel(invitationChannel);
    await androidPlugin.createNotificationChannel(messageChannel);
    await androidPlugin.createNotificationChannel(defaultChannel);
  }

  /// 初始化FCM
  Future<void> _initializeFCM() async {
    try {
      // 请求权限
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('FCM permission granted');
        
        // 设置全局消息处理器
        _fcmForegroundListener = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        _fcmBackgroundListener = FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);
        
        // 检查应用启动时的通知
        RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
        if (initialMessage != null) {
          _handleBackgroundMessage(initialMessage);
        }
      }
    } catch (e) {
      print('Error initializing FCM: $e');
    }
  }

  /// 启动用户特定的监听器
  Future<void> startUserListeners(String userId, {
    Function(String, Map<String, dynamic>)? onInvitationReceived,
    Function(RemoteMessage)? onMessageReceived,
  }) async {
    print('=== Starting User Listeners for: $userId ===');
    
    // 确保初始化完成
    if (!_isInitialized) {
      print('Global notification manager not initialized, initializing now...');
      await initialize();
    }

    // 停止之前的监听器
    await stopUserListeners();

    _currentUserId = userId;
    _onInvitationReceived = onInvitationReceived;
    _onMessageReceived = onMessageReceived;
    
    print('=== CALLBACK SETUP ===');
    print('_onInvitationReceived set: ${_onInvitationReceived != null}');
    print('_onMessageReceived set: ${_onMessageReceived != null}');

    try {
      // 请求通知权限（重要：确保每个设备都有权限）
      await _requestNotificationPermissions();
      
      // 获取并保存FCM令牌
      await _saveFCMToken(userId);
      
      // 启动RTDB监听器
      await _startInvitationListener(userId);
      await _startCustomMessageListener(userId);
      
      _listenersActive = true;
      print('User listeners started successfully');
      
      // 验证回调函数是否正确设置
      print('=== FINAL CALLBACK VERIFICATION ===');
      print('_onInvitationReceived: ${_onInvitationReceived != null}');
      print('_onMessageReceived: ${_onMessageReceived != null}');
      print('_listenersActive: $_listenersActive');
      
      // 输出调试信息
      await _debugNotificationSetup();
    } catch (e) {
      print('Error starting user listeners: $e');
    }
  }

  /// 请求通知权限
  Future<void> _requestNotificationPermissions() async {
    try {
      // 请求本地通知权限
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        print('Local notification permission granted: $granted');
      }
      
      // 请求FCM权限
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      
      print('FCM permission status: ${settings.authorizationStatus}');
      print('Alert setting: ${settings.alert}');
      print('Badge setting: ${settings.badge}');
      print('Sound setting: ${settings.sound}');
    } catch (e) {
      print('Error requesting notification permissions: $e');
    }
  }

  /// 调试通知设置
  Future<void> _debugNotificationSetup() async {
    try {
      // 检查FCM令牌
      String? token = await _firebaseMessaging.getToken();
      print('=== NOTIFICATION DEBUG INFO ===');
      print('FCM Token available: ${token != null}');
      if (token != null) {
        print('FCM Token (first 20 chars): ${token.substring(0, 20)}...');
      }
      
      // 检查本地通知权限
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final enabled = await androidPlugin.areNotificationsEnabled();
        print('Local notifications enabled: $enabled');
      }
      
      // 检查监听器状态
      print('Invitation listener active: ${_invitationListener != null}');
      print('Custom message listener active: ${_customMessageListener != null}');
      print('FCM foreground listener active: ${_fcmForegroundListener != null}');
      print('FCM background listener active: ${_fcmBackgroundListener != null}');
      print('Current user ID: $_currentUserId');
      print('=== END DEBUG INFO ===');
    } catch (e) {
      print('Error in debug info: $e');
    }
  }

  /// 保存FCM令牌
  Future<void> _saveFCMToken(String userId) async {
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        // 尝试保存到用户可写的路径
        try {
          await _database.child('users/$userId/fcm_token').set({
            'token': token,
            'platform': 'android', 
            'timestamp': DateTime.now().toIso8601String(),
            'app_version': '1.0.0',
          });
          print('FCM token saved for user: $userId');
        } catch (e) {
          // 如果保存失败，记录但不阻止功能
          print('Warning: Could not save FCM token to database: $e');
          print('FCM push notifications may not work, but RTDB notifications will still function');
        }
        
        // 监听令牌刷新
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          _saveFCMToken(userId);
        });
      }
    } catch (e) {
      print('Error getting FCM token: $e');
    }
  }

  /// 启动邀请监听器
  Future<void> _startInvitationListener(String userId) async {
    final invitationsRef = _database.child('invitations/$userId');
    
    _invitationListener = invitationsRef.onChildAdded.listen(
      (DatabaseEvent event) async {
        print('=== GLOBAL INVITATION LISTENER ===');
        print('Event key: ${event.snapshot.key}');
        print('Event data: ${event.snapshot.value}');
        
        if (event.snapshot.value != null) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          final eventKey = event.snapshot.key ?? '';
          final supervisionId = data['supervisionId']?.toString() ?? '';
          
          // 创建唯一标识符用于去重
          final notificationId = '${eventKey}_${supervisionId}_invitation';
          
          // 检查是否已经处理过这个通知（仅用于通知显示去重）
          bool isNotificationDuplicate = _processedNotifications.contains(notificationId);
          
          if (!isNotificationDuplicate) {
            // 标记为已处理（仅用于通知去重）
            _processedNotifications.add(notificationId);
            print('Processing new invitation notification: $notificationId');
            
            // 显示本地通知
            await _showInvitationNotification(
              title: data['title']?.toString() ?? 'Supervisor Invitation',
              body: data['message']?.toString() ?? 'You have received a supervisor invitation',
              data: Map<String, String>.from(data.map((k, v) => MapEntry(k.toString(), v.toString()))),
            );
          } else {
            print('Notification already shown, but will still show dialog: $notificationId');
          }
          
          // 始终触发回调显示对话框（即使通知已显示过）
          print('=== CALLBACK CHECK BEFORE TRIGGER ===');
          print('_onInvitationReceived: ${_onInvitationReceived != null}');
          print('_listenersActive: $_listenersActive');
          print('_currentUserId: $_currentUserId');
          
          if (_onInvitationReceived != null) {
            final supervisionData = {
              'InviterUserName': data['inviterName'] ?? 'Unknown',
              'InviterId': data['inviterId'] ?? '',
              'SupervisionId': supervisionId,
            };
            print('Triggering invitation dialog callback for: $supervisionId');
            _onInvitationReceived!(supervisionId, supervisionData);
          } else {
            print('ERROR: _onInvitationReceived callback is null!');
            print('This means startUserListeners was not called or failed');
          }
          
          // 删除已处理的通知
          await event.snapshot.ref.remove();
          
          // 启动清理定时器
          _startCleanupTimer();
        }
      },
      onError: (error) {
        print('Invitation listener error: $error');
      },
    );
  }

  /// 启动自定义消息监听器
  Future<void> _startCustomMessageListener(String userId) async {
    final notificationsRef = _database.child('notifications/$userId');
    
    _customMessageListener = notificationsRef.onChildAdded.listen(
      (DatabaseEvent event) async {
        print('=== GLOBAL CUSTOM MESSAGE LISTENER ===');
        print('Event key: ${event.snapshot.key}');
        print('Event data: ${event.snapshot.value}');
        
        if (event.snapshot.value != null) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          
          // 显示本地通知
          final messageType = data['type']?.toString() ?? '';
          final senderName = data['senderName']?.toString() ?? 'CalorieCare';
          String title = data['title']?.toString() ?? 'Notification';
          
          // 根据消息类型调整标题
          if (messageType == 'log_food_reminder') {
            title = 'Reminder from $senderName';
          } else if (data['senderName'] != null && data['senderName'] != 'CalorieCare') {
            title = 'Message from $senderName';
          }
          
          await _showCustomMessageNotification(
            title: title,
            body: data['message']?.toString() ?? 'You have a new message',
            data: Map<String, String>.from(data.map((k, v) => MapEntry(k.toString(), v.toString()))),
          );
          
          // 删除已处理的通知
          await event.snapshot.ref.remove();
        }
      },
      onError: (error) {
        print('Custom message listener error: $error');
      },
    );
  }

  /// 处理前台FCM消息
  void _handleForegroundMessage(RemoteMessage message) {
    print('=== GLOBAL FCM FOREGROUND MESSAGE ===');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');
    print('Data: ${message.data}');
    
    // 显示本地通知
    _showFCMNotification(message);
    
    // 触发回调
    if (_onMessageReceived != null) {
      _onMessageReceived!(message);
    }
  }

  /// 处理背景FCM消息
  void _handleBackgroundMessage(RemoteMessage message) {
    print('=== GLOBAL FCM BACKGROUND MESSAGE ===');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');
    print('Data: ${message.data}');
    
    // 触发回调
    if (_onMessageReceived != null) {
      _onMessageReceived!(message);
    }
  }

  /// 显示邀请通知
  Future<void> _showInvitationNotification({
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'supervisor_invitations_channel',
      'Supervisor Invitations',
      channelDescription: 'Notifications for supervisor invitations',
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
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: 'supervisor_invitation',
    );
    
    print('Invitation notification displayed: $title');
  }

  /// 显示自定义消息通知
  Future<void> _showCustomMessageNotification({
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'custom_messages_channel',
      'Custom Messages',
      channelDescription: 'Notifications for custom messages from supervisors',
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
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: 'custom_message',
    );
    
    print('Custom message notification displayed: $title');
  }

  /// 显示FCM通知
  Future<void> _showFCMNotification(RemoteMessage message) async {
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
      payload: 'fcm_message',
    );
    
    print('FCM notification displayed: ${notification.title}');
  }

  /// 通知点击处理
  void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    // 这里可以根据payload执行相应的导航操作
  }

  /// 停止用户监听器
  Future<void> stopUserListeners() async {
    print('=== Stopping User Listeners ===');
    
    _invitationListener?.cancel();
    _customMessageListener?.cancel();
    
    _invitationListener = null;
    _customMessageListener = null;
    
    _currentUserId = null;
    _listenersActive = false;
    _onInvitationReceived = null;
    _onMessageReceived = null;
    
    print('User listeners stopped');
  }

  /// 发送RTDB通知（简化版本）
  Future<void> sendRTDBNotification({
    required String receiverId,
    required String type, // 'invitation' or 'notification'
    required Map<String, dynamic> data,
  }) async {
    try {
      final path = type == 'invitation' ? 'invitations/$receiverId' : 'notifications/$receiverId';
      await _database.child(path).push().set(data);
      print('RTDB notification sent to $receiverId via $path');
      print('Data: $data');
    } catch (e) {
      print('Error sending RTDB notification: $e');
    }
  }

  /// 发送Log Food提醒通知
  Future<void> sendLogFoodReminder(String userId, {String? senderName}) async {
    try {
      print('=== SENDING LOG FOOD REMINDER ===');
      final title = senderName != null ? 'Reminder from $senderName' : 'Log Food Reminder';
      await sendRTDBNotification(
        receiverId: userId,
        type: 'notification',
        data: {
          'title': title,
          'message': 'Don\'t forget to log your meals today! Keep track of your daily intake.',
          'senderId': senderName != null ? 'supervisor' : 'system',
          'senderName': senderName ?? 'CalorieCare',
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'log_food_reminder',
        },
      );
      print('Log food reminder sent successfully');
    } catch (e) {
      print('Error sending log food reminder: $e');
    }
  }

  /// 获取状态信息
  Map<String, dynamic> getStatus() {
    return {
      'isInitialized': _isInitialized,
      'listenersActive': _listenersActive,
      'currentUserId': _currentUserId,
      'hasInvitationListener': _invitationListener != null,
      'hasCustomMessageListener': _customMessageListener != null,
      'hasFCMListeners': _fcmForegroundListener != null && _fcmBackgroundListener != null,
    };
  }

  /// 启动清理定时器
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(Duration(minutes: 5), () {
      // 每5分钟清理一次已处理通知记录，防止内存泄漏
      final currentTime = DateTime.now();
      _processedNotifications.clear();
      print('Cleaned up processed notifications cache');
    });
  }

  /// 清理资源
  void dispose() {
    print('=== Disposing Global Notification Manager ===');
    
    stopUserListeners();
    
    _fcmForegroundListener?.cancel();
    _fcmBackgroundListener?.cancel();
    _cleanupTimer?.cancel();
    
    _fcmForegroundListener = null;
    _fcmBackgroundListener = null;
    _cleanupTimer = null;
    
    _processedNotifications.clear();
    _isInitialized = false;
    
    print('Global Notification Manager disposed');
  }
}
