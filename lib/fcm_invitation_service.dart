import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:caloriecare/fcm_service.dart';
import 'dart:async';

class FCMInvitationService {
  static final FCMInvitationService _instance = FCMInvitationService._internal();
  factory FCMInvitationService() => _instance;
  FCMInvitationService._internal();

  final FCMService _fcmService = FCMService();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  String? _currentUserId;
  
  // 回调函数，用于通知homepage显示对话框
  Function(String, Map<String, dynamic>)? _onInvitationReceived;

  /// 初始化FCM邀请通知服务
  Future<void> initialize(String userId) async {
    print('=== Initializing FCM Invitation Service ===');
    _currentUserId = userId;
    
    try {
      // 初始化FCM服务
      await _fcmService.initialize(userId);
      
      // 设置消息处理器
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
      
      // 检查应用启动时的通知
      RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }
      
      print('FCM Invitation Service initialized successfully');
    } catch (e) {
      print('Error initializing FCM invitation service: $e');
    }
  }

  /// 设置邀请接收回调
  void setInvitationCallback(Function(String, Map<String, dynamic>) callback) {
    _onInvitationReceived = callback;
  }

  /// 处理前台消息
  void _handleForegroundMessage(RemoteMessage message) {
    print('=== FCM Foreground Message ===');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');
    print('Data: ${message.data}');
    
    // 检查是否是邀请通知
    if (message.data['type'] == 'supervisor_invitation') {
      _handleInvitationMessage(message);
    }
  }

  /// 处理消息点击打开应用
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('=== FCM Message Opened App ===');
    print('Title: ${message.notification?.title}');
    print('Body: ${message.notification?.body}');
    print('Data: ${message.data}');
    
    // 检查是否是邀请通知
    if (message.data['type'] == 'supervisor_invitation') {
      _handleInvitationMessage(message);
    }
  }

  /// 处理邀请消息
  void _handleInvitationMessage(RemoteMessage message) {
    try {
      final data = message.data;
      
      if (data.containsKey('supervisionId') && 
          data.containsKey('inviterId') && 
          data.containsKey('inviterName')) {
        
        print('=== Processing Invitation Message ===');
        print('SupervisionID: ${data['supervisionId']}');
        print('InviterID: ${data['inviterId']}');
        print('InviterName: ${data['inviterName']}');
        
        // 触发回调，通知homepage显示对话框
        if (_onInvitationReceived != null) {
          final supervisionData = {
            'InviterUserName': data['inviterName'] ?? 'Unknown',
            'InviterId': data['inviterId'] ?? '',
            'SupervisionId': data['supervisionId'] ?? '',
          };
          
          _onInvitationReceived!(data['supervisionId'] ?? '', supervisionData);
        }
      }
    } catch (e) {
      print('Error handling invitation message: $e');
    }
  }

  /// 发送FCM邀请通知
  Future<bool> sendInvitationNotification({
    required String receiverId,
    required String inviterId,
    required String inviterName,
    required String supervisionId,
  }) async {
    try {
      print('=== Sending FCM Invitation ===');
      print('From: $inviterName ($inviterId)');
      print('To: $receiverId');
      print('SupervisionID: $supervisionId');
      
      // 使用FCM服务发送通知
      final success = await _fcmService.sendInvitationNotification(
        receiverId: receiverId,
        inviterId: inviterId,
        inviterName: inviterName,
        supervisionId: supervisionId,
      );
      
      if (success) {
        print('=== FCM Invitation Sent Successfully ===');
        
        // 可选：同时保存到RTDB作为备用机制
        await _saveInvitationToRTDB({
          'receiverId': receiverId,
          'inviterId': inviterId,
          'inviterName': inviterName,
          'supervisionId': supervisionId,
          'timestamp': DateTime.now().toIso8601String(),
          'method': 'fcm',
        });
      } else {
        print('=== FCM Invitation Failed ===');
        
        // FCM失败时回退到RTDB通知
        await _fallbackToRTDBNotification(
          receiverId: receiverId,
          inviterId: inviterId,
          inviterName: inviterName,
          supervisionId: supervisionId,
        );
      }
      
      return success;
    } catch (e) {
      print('Error sending FCM invitation: $e');
      
      // 出错时回退到RTDB通知
      await _fallbackToRTDBNotification(
        receiverId: receiverId,
        inviterId: inviterId,
        inviterName: inviterName,
        supervisionId: supervisionId,
      );
      
      return false;
    }
  }

  /// 保存邀请信息到RTDB（用于记录和备用）
  Future<void> _saveInvitationToRTDB(Map<String, dynamic> invitationData) async {
    try {
      await _database.child('invitation_logs').push().set(invitationData);
      print('Invitation logged to RTDB');
    } catch (e) {
      print('Error saving invitation to RTDB: $e');
    }
  }

  /// 回退到RTDB通知机制
  Future<void> _fallbackToRTDBNotification({
    required String receiverId,
    required String inviterId,
    required String inviterName,
    required String supervisionId,
  }) async {
    try {
      print('=== Fallback to RTDB Notification ===');
      
      final invitationData = {
        'title': 'Supervisor Invitation',
        'message': '$inviterName invites you to become mutual supervisors',
        'inviterId': inviterId,
        'inviterName': inviterName,
        'supervisionId': supervisionId,
        'timestamp': DateTime.now().toIso8601String(),
        'method': 'rtdb_fallback',
      };
      
      // 在RTDB中创建邀请通知作为备用
      final newRef = await _database.child('invitations/$receiverId').push();
      await newRef.set(invitationData);
      
      print('=== RTDB Fallback Notification Sent ===');
      print('RTDB Path: invitations/$receiverId/${newRef.key}');
    } catch (e) {
      print('Error in RTDB fallback: $e');
    }
  }

  /// 获取当前用户ID
  String? get currentUserId => _currentUserId;

  /// 获取FCM令牌
  String? get fcmToken => _fcmService.currentToken;

  /// 清理资源
  void dispose() {
    _currentUserId = null;
    _onInvitationReceived = null;
  }
}
