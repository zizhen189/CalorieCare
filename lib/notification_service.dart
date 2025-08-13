import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // 存储监听器引用，用于清理
  StreamSubscription<DatabaseEvent>? _customMessageListener;
  String? _currentUserId;

  /// 初始化通知服务
  Future<void> initialize() async {
    print('=== Initializing Notification Service ===');
    
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    try {
      await _notifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      print('Notification service initialized successfully');
      
      // 检查通知权限
      final isGranted = await _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
      print('Notification permission granted: $isGranted');
    } catch (e) {
      print('Error initializing notification service: $e');
    }
  }

  /// 启动RTDB监听器
  Future<void> startCustomMessageListener(String userId) async {
    // 停止之前的监听器
    stopCustomMessageListener();
    
    _currentUserId = userId;
    
    print('Starting custom message listener for user: $userId');
    
    // 监听用户的通知路径
    final notificationsRef = _database.child('notifications/$userId');
    
    _customMessageListener = notificationsRef.onChildAdded.listen(
      (DatabaseEvent event) async {
        print('Received RTDB event: ${event.type}');
        print('Event data: ${event.snapshot.value}');
        
        if (event.snapshot.value != null) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          final notificationId = event.snapshot.key;
          
          print('Processing notification: $notificationId');
          print('Notification data: $data');
          
          // 显示通知
          await showCustomMessageNotification(
            title: data['title'] ?? 'New Message',
            body: data['message'] ?? 'You have a new message',
            senderId: data['senderId'] ?? '',
            senderName: data['senderName'] ?? 'Unknown',
            timestamp: data['timestamp'] ?? DateTime.now().toIso8601String(),
          );
          
          // 删除已处理的通知
          await event.snapshot.ref.remove();
          print('Notification processed and removed: $notificationId');
        }
      },
      onError: (error) {
        print('Error listening to custom messages: $error');
      },
    );
    
    print('Custom message listener started successfully for user: $userId');
  }

  /// 停止RTDB监听器
  void stopCustomMessageListener() {
    _customMessageListener?.cancel();
    _customMessageListener = null;
    _currentUserId = null;
    print('Stopped custom message listener');
  }

  /// 发送自定义消息通知
  Future<void> sendCustomMessage({
    required String receiverId,
    required String message,
    required String senderId,
    required String senderName,
  }) async {
    try {
      final notificationData = {
        'title': 'New Message from $senderName',
        'message': message,
        'senderId': senderId,
        'senderName': senderName,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // 在RTDB中创建通知
      await _database.child('notifications/$receiverId').push().set(notificationData);
      
      print('Custom message sent to user: $receiverId');
    } catch (e) {
      print('Error sending custom message: $e');
    }
  }

  /// 显示自定义消息通知
  Future<void> showCustomMessageNotification({
    required String title,
    required String body,
    required String senderId,
    required String senderName,
    required String timestamp,
  }) async {
    print('Attempting to show notification: $title - $body');
    
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'custom_messages_channel',
      'Custom Messages',
      channelDescription: 'Notifications for custom messages from supervisors',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      channelShowBadge: true,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    try {
      final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      
      await _notifications.show(
        notificationId,
        title,
        body,
        platformChannelSpecifics,
        payload: 'custom_message',
      );
      
      print('Notification displayed successfully with ID: $notificationId');
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  /// 通知被点击时的回调
  void _onNotificationTapped(NotificationResponse response) {
    // 这里可以处理通知点击事件
    print('Notification tapped: ${response.payload}');
  }

  /// 显示卡路里调整通知
  Future<void> showCalorieAdjustmentNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    print('=== Show Calorie Adjustment Notification ===');
    print('Title: $title');
    print('Body: $body');
    print('Payload: $payload');
    
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'calorie_adjustment_channel',
      'Calorie Adjustment Notifications',
      channelDescription: 'Notifications for calorie target adjustments',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    try {
      final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      await _notifications.show(
        notificationId,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );
      print('Calorie adjustment notification sent successfully with ID: $notificationId');
    } catch (e) {
      print('Error showing calorie adjustment notification: $e');
    }
  }

  /// 显示每日调整通知
  Future<void> showDailyAdjustmentNotification({
    required int previousTarget,
    required int newTarget,
    required int adjustment,
    required String reason,
  }) async {
    final title = 'Daily Calorie Target Adjusted';
    final body = 'Your daily target has been adjusted from $previousTarget to $newTarget calories (${adjustment > 0 ? '+' : ''}$adjustment).\n\nReason: $reason';
    
    print('=== Daily Adjustment Notification ===');
    print('Title: $title');
    print('Body: $body');
    print('Previous target: $previousTarget');
    print('New target: $newTarget');
    print('Adjustment: $adjustment');
    print('Reason: $reason');
    
    await showCalorieAdjustmentNotification(
      title: title,
      body: body,
      payload: 'daily_adjustment',
    );
    
    print('Daily adjustment notification sent to system');
  }

  /// 显示每周调整通知
  Future<void> showWeeklyAdjustmentNotification({
    required int previousTarget,
    required int newTarget,
    required int adjustment,
    required String reason,
    required int daysAnalyzed,
  }) async {
    final title = 'Weekly Calorie Target Adjusted';
    final body = 'Based on your $daysAnalyzed-day intake pattern, your daily target has been adjusted from $previousTarget to $newTarget calories (${adjustment > 0 ? '+' : ''}$adjustment).\n\nReason: $reason';
    
    await showCalorieAdjustmentNotification(
      title: title,
      body: body,
      payload: 'weekly_adjustment',
    );
  }

  /// 显示自动调整完成通知
  Future<void> showAutoAdjustmentNotification({
    required Map<String, dynamic> result,
  }) async {
    print('=== Auto Adjustment Notification Debug ===');
    print('Result: $result');
    
    if (result['daily']?['success'] == true) {
      final daily = result['daily'];
      print('Daily adjustment success, showing notification...');
      print('Previous target: ${daily['previousTarget']}');
      print('New target: ${daily['newTarget']}');
      print('Adjustment: ${daily['adjustment']}');
      
      await showDailyAdjustmentNotification(
        previousTarget: daily['previousTarget'].round(),
        newTarget: daily['newTarget'].round(),
        adjustment: daily['adjustment'].round(),
        reason: daily['reason'] ?? 'Daily intake adjustment',
      );
      print('Daily adjustment notification sent successfully');
    } else {
      print('Daily adjustment not successful or not present');
    }

    if (result['weekly']?['success'] == true) {
      final weekly = result['weekly'];
      print('Weekly adjustment success, showing notification...');
      await showWeeklyAdjustmentNotification(
        previousTarget: weekly['previousTarget'].round(),
        newTarget: weekly['newTarget'].round(),
        adjustment: weekly['adjustment'].round(),
        reason: weekly['reason'] ?? 'Weekly pattern adjustment',
        daysAnalyzed: weekly['daysAnalyzed'] ?? 7,
      );
      print('Weekly adjustment notification sent successfully');
    } else {
      print('Weekly adjustment not successful or not present');
    }
    
    print('=== End Auto Adjustment Notification Debug ===');
  }

  /// 取消所有通知
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// 取消特定通知
  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }
} 