import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:caloriecare/fcm_service.dart';
import 'dart:async';

class FCMNotificationService {
  static final FCMNotificationService _instance = FCMNotificationService._internal();
  factory FCMNotificationService() => _instance;
  FCMNotificationService._internal();

  final FCMService _fcmService = FCMService();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  String? _currentUserId;

  /// 初始化FCM通知服务
  Future<void> initialize(String userId) async {
    print('=== Initializing FCM Notification Service ===');
    _currentUserId = userId;
    
    try {
      // 初始化FCM服务（如果还没有初始化）
      await _fcmService.initialize(userId);
      
      // 设置消息处理器
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
      
      // 检查应用启动时的通知
      RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }
      
      print('FCM Notification Service initialized successfully');
    } catch (e) {
      print('Error initializing FCM notification service: $e');
    }
  }

  /// 处理前台消息
  void _handleForegroundMessage(RemoteMessage message) {
    print('=== FCM Foreground Notification ===');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');
    print('Data: ${message.data}');
    
    // 检查消息类型并处理
    final messageType = message.data['type'];
    switch (messageType) {
      case 'custom_message':
        _handleCustomMessage(message);
        break;
      case 'calorie_adjustment':
        _handleCalorieAdjustment(message);
        break;
      default:
        print('Unknown message type: $messageType');
        break;
    }
  }

  /// 处理消息点击打开应用
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('=== FCM Notification Opened App ===');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');
    print('Data: ${message.data}');
    
    // 根据消息类型执行相应的导航或操作
    final messageType = message.data['type'];
    switch (messageType) {
      case 'custom_message':
        // 可以导航到消息页面
        print('Navigate to custom message page');
        break;
      case 'calorie_adjustment':
        // 可以导航到卡路里调整页面
        print('Navigate to calorie adjustment page');
        break;
      case 'supervisor_invitation':
        // 可以导航到邀请页面
        print('Navigate to invitation page');
        break;
      default:
        print('Unknown message type for navigation: $messageType');
        break;
    }
  }

  /// 处理自定义消息
  void _handleCustomMessage(RemoteMessage message) {
    print('=== Processing Custom Message ===');
    final data = message.data;
    print('Sender: ${data['senderName']}');
    print('Message: ${data['message']}');
    print('Timestamp: ${data['timestamp']}');
    
    // 这里可以执行自定义消息的特定处理逻辑
    // 比如保存到本地数据库、更新UI等
  }

  /// 处理卡路里调整通知
  void _handleCalorieAdjustment(RemoteMessage message) {
    print('=== Processing Calorie Adjustment ===');
    final data = message.data;
    print('Adjustment Data: ${data['adjustmentData']}');
    print('Timestamp: ${data['timestamp']}');
    
    // 这里可以执行卡路里调整的特定处理逻辑
    // 比如更新用户的卡路里目标、刷新UI等
  }

  /// 发送FCM自定义消息
  Future<bool> sendCustomMessage({
    required String receiverId,
    required String message,
    required String senderId,
    required String senderName,
  }) async {
    try {
      print('=== Sending FCM Custom Message ===');
      print('From: $senderName ($senderId)');
      print('To: $receiverId');
      print('Message: $message');
      
      // 使用FCM服务发送通知
      final success = await _fcmService.sendCustomMessage(
        receiverId: receiverId,
        senderId: senderId,
        senderName: senderName,
        message: message,
      );
      
      if (success) {
        print('=== FCM Custom Message Sent Successfully ===');
        
        // 可选：保存消息到数据库作为记录
        await _saveMessageToDatabase({
          'receiverId': receiverId,
          'senderId': senderId,
          'senderName': senderName,
          'message': message,
          'timestamp': DateTime.now().toIso8601String(),
          'method': 'fcm',
        });
      } else {
        print('=== FCM Custom Message Failed ===');
        
        // FCM失败时回退到RTDB通知
        await _fallbackToRTDBMessage(
          receiverId: receiverId,
          senderId: senderId,
          senderName: senderName,
          message: message,
        );
      }
      
      return success;
    } catch (e) {
      print('Error sending FCM custom message: $e');
      
      // 出错时回退到RTDB通知
      await _fallbackToRTDBMessage(
        receiverId: receiverId,
        senderId: senderId,
        senderName: senderName,
        message: message,
      );
      
      return false;
    }
  }

  /// 发送FCM卡路里调整通知
  Future<bool> sendCalorieAdjustmentNotification({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> adjustmentData,
  }) async {
    try {
      print('=== Sending FCM Calorie Adjustment ===');
      print('To: $userId');
      print('Title: $title');
      print('Body: $body');
      
      // 使用FCM服务发送通知
      final success = await _fcmService.sendCalorieAdjustmentNotification(
        userId: userId,
        title: title,
        body: body,
        adjustmentData: adjustmentData,
      );
      
      if (success) {
        print('=== FCM Calorie Adjustment Sent Successfully ===');
        
        // 保存调整记录到数据库
        await _saveAdjustmentToDatabase({
          'userId': userId,
          'title': title,
          'body': body,
          'adjustmentData': adjustmentData,
          'timestamp': DateTime.now().toIso8601String(),
          'method': 'fcm',
        });
      } else {
        print('=== FCM Calorie Adjustment Failed ===');
      }
      
      return success;
    } catch (e) {
      print('Error sending FCM calorie adjustment: $e');
      return false;
    }
  }

  /// 保存消息到数据库
  Future<void> _saveMessageToDatabase(Map<String, dynamic> messageData) async {
    try {
      await _database.child('message_logs').push().set(messageData);
      print('Message logged to database');
    } catch (e) {
      print('Error saving message to database: $e');
    }
  }

  /// 保存调整记录到数据库
  Future<void> _saveAdjustmentToDatabase(Map<String, dynamic> adjustmentData) async {
    try {
      await _database.child('adjustment_logs').push().set(adjustmentData);
      print('Adjustment logged to database');
    } catch (e) {
      print('Error saving adjustment to database: $e');
    }
  }

  /// 回退到RTDB消息机制
  Future<void> _fallbackToRTDBMessage({
    required String receiverId,
    required String senderId,
    required String senderName,
    required String message,
  }) async {
    try {
      print('=== Fallback to RTDB Message ===');
      
      final messageData = {
        'title': 'New Message from $senderName',
        'message': message,
        'senderId': senderId,
        'senderName': senderName,
        'timestamp': DateTime.now().toIso8601String(),
        'method': 'rtdb_fallback',
      };
      
      // 在RTDB中创建消息通知作为备用
      final newRef = await _database.child('notifications/$receiverId').push();
      await newRef.set(messageData);
      
      print('=== RTDB Fallback Message Sent ===');
      print('RTDB Path: notifications/$receiverId/${newRef.key}');
    } catch (e) {
      print('Error in RTDB message fallback: $e');
    }
  }

  /// 显示每日调整通知
  Future<void> showDailyAdjustmentNotification({
    required int previousTarget,
    required int newTarget,
    required int adjustment,
    required String reason,
  }) async {
    if (_currentUserId == null) {
      print('No current user for adjustment notification');
      return;
    }
    
    final title = 'Daily Calorie Target Adjusted';
    final body = 'Your daily target has been adjusted from $previousTarget to $newTarget calories (${adjustment > 0 ? '+' : ''}$adjustment).\n\nReason: $reason';
    
    final adjustmentData = {
      'type': 'daily',
      'previousTarget': previousTarget,
      'newTarget': newTarget,
      'adjustment': adjustment,
      'reason': reason,
    };
    
    await sendCalorieAdjustmentNotification(
      userId: _currentUserId!,
      title: title,
      body: body,
      adjustmentData: adjustmentData,
    );
  }

  /// 显示每周调整通知
  Future<void> showWeeklyAdjustmentNotification({
    required int previousTarget,
    required int newTarget,
    required int adjustment,
    required String reason,
    required int daysAnalyzed,
  }) async {
    if (_currentUserId == null) {
      print('No current user for adjustment notification');
      return;
    }
    
    final title = 'Weekly Calorie Target Adjusted';
    final body = 'Based on your $daysAnalyzed-day intake pattern, your daily target has been adjusted from $previousTarget to $newTarget calories (${adjustment > 0 ? '+' : ''}$adjustment).\n\nReason: $reason';
    
    final adjustmentData = {
      'type': 'weekly',
      'previousTarget': previousTarget,
      'newTarget': newTarget,
      'adjustment': adjustment,
      'reason': reason,
      'daysAnalyzed': daysAnalyzed,
    };
    
    await sendCalorieAdjustmentNotification(
      userId: _currentUserId!,
      title: title,
      body: body,
      adjustmentData: adjustmentData,
    );
  }

  /// 显示自动调整完成通知
  Future<void> showAutoAdjustmentNotification({
    required Map<String, dynamic> result,
  }) async {
    print('=== Auto Adjustment FCM Notification ===');
    print('Result: $result');
    
    if (result['daily']?['success'] == true) {
      final daily = result['daily'];
      await showDailyAdjustmentNotification(
        previousTarget: daily['previousTarget'].round(),
        newTarget: daily['newTarget'].round(),
        adjustment: daily['adjustment'].round(),
        reason: daily['reason'] ?? 'Daily intake adjustment',
      );
    }

    if (result['weekly']?['success'] == true) {
      final weekly = result['weekly'];
      await showWeeklyAdjustmentNotification(
        previousTarget: weekly['previousTarget'].round(),
        newTarget: weekly['newTarget'].round(),
        adjustment: weekly['adjustment'].round(),
        reason: weekly['reason'] ?? 'Weekly pattern adjustment',
        daysAnalyzed: weekly['daysAnalyzed'] ?? 7,
      );
    }
  }

  /// 获取当前用户ID
  String? get currentUserId => _currentUserId;

  /// 获取FCM令牌
  String? get fcmToken => _fcmService.currentToken;

  /// 清理资源
  void dispose() {
    _currentUserId = null;
  }
}
