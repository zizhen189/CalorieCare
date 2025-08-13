import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class InvitationNotificationService {
  static final InvitationNotificationService _instance = InvitationNotificationService._internal();
  factory InvitationNotificationService() => _instance;
  InvitationNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // 存储监听器引用，用于清理
  StreamSubscription<DatabaseEvent>? _invitationListener;
  String? _currentUserId;
  
  // 回调函数，用于通知homepage显示对话框
  Function(String, Map<String, dynamic>)? _onInvitationReceived;

  /// 初始化通知服务
  Future<void> initialize() async {
    print('=== Initializing Invitation Notification Service ===');
    
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
      print('Invitation notification service initialized successfully');
      
      // 检查通知权限
      final isGranted = await _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
      print('Invitation notification permission granted: $isGranted');
    } catch (e) {
      print('Error initializing invitation notification service: $e');
    }
  }

  /// 启动RTDB监听器
  Future<void> startInvitationListener(String userId, {Function(String, Map<String, dynamic>)? onInvitationReceived}) async {
    // 停止之前的监听器
    stopInvitationListener();
    
    _currentUserId = userId;
    _onInvitationReceived = onInvitationReceived;
    
    print('Starting invitation listener for user: $userId');
    
    // 监听用户的邀请路径
    final invitationsRef = _database.child('invitations/$userId');
    
    _invitationListener = invitationsRef.onChildAdded.listen(
      (DatabaseEvent event) async {
        print('=== RECEIVED INVITATION RTDB EVENT ===');
        print('Event type: ${event.type}');
        print('Event key: ${event.snapshot.key}');
        print('Event data: ${event.snapshot.value}');
        
        if (event.snapshot.value != null) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          final invitationId = event.snapshot.key;
          
          print('=== PROCESSING INVITATION ===');
          print('Invitation ID: $invitationId');
          print('Invitation data: $data');
          
          // 显示邀请通知
          await showInvitationNotification(
            title: data['title'] ?? 'Supervisor Invitation',
            body: data['message'] ?? 'You have received a supervisor invitation',
            inviterId: data['inviterId'] ?? '',
            inviterName: data['inviterName'] ?? 'Unknown',
            supervisionId: data['supervisionId'] ?? '',
            timestamp: data['timestamp'] ?? DateTime.now().toIso8601String(),
          );
          
          // 触发回调，通知homepage显示对话框
          if (_onInvitationReceived != null) {
            final supervisionData = {
              'InviterUserName': data['inviterName'] ?? 'Unknown',
              'InviterId': data['inviterId'] ?? '',
              'SupervisionId': data['supervisionId'] ?? '',
            };
            // 传递SupervisionID而不是RTDB的invitationId
            _onInvitationReceived!(data['supervisionId'] ?? '', supervisionData);
          }
          
          // 删除已处理的通知
          await event.snapshot.ref.remove();
          print('=== INVITATION PROCESSED AND REMOVED ===');
          print('Invitation ID: $invitationId');
          print('Removed from RTDB path: invitations/$_currentUserId/$invitationId');
        }
      },
      onError: (error) {
        print('=== INVITATION LISTENER ERROR ===');
        print('Error: $error');
      },
    );
    
    print('Invitation listener started successfully for user: $userId');
  }

  /// 停止RTDB监听器
  void stopInvitationListener() {
    _invitationListener?.cancel();
    _invitationListener = null;
    _currentUserId = null;
    print('Stopped invitation listener');
  }

  /// 发送邀请通知到RTDB
  Future<void> sendInvitationNotification({
    required String receiverId,
    required String inviterId,
    required String inviterName,
    required String supervisionId,
  }) async {
    try {
      final invitationData = {
        'title': 'Supervisor Invitation',
        'message': '$inviterName invites you to become mutual supervisors',
        'inviterId': inviterId,
        'inviterName': inviterName,
        'supervisionId': supervisionId,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      print('=== RTDB INVITATION DATA ===');
      print('Data to be sent: $invitationData');
      print('RTDB Path: invitations/$receiverId');
      
      // 在RTDB中创建邀请通知
      final newRef = await _database.child('invitations/$receiverId').push();
      await newRef.set(invitationData);
      
      print('=== RTDB INVITATION SENT ===');
      print('Invitation notification sent to user: $receiverId');
      print('RTDB Key: ${newRef.key}');
      print('Full RTDB Path: invitations/$receiverId/${newRef.key}');
    } catch (e) {
      print('Error sending invitation notification: $e');
    }
  }

  /// 显示邀请通知
  Future<void> showInvitationNotification({
    required String title,
    required String body,
    required String inviterId,
    required String inviterName,
    required String supervisionId,
    required String timestamp,
  }) async {
    print('Attempting to show invitation notification: $title - $body');
    
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'supervisor_invitations_channel',
      'Supervisor Invitations',
      channelDescription: 'Notifications for supervisor invitations',
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
        payload: 'supervisor_invitation',
      );
      
      print('Invitation notification displayed successfully with ID: $notificationId');
    } catch (e) {
      print('Error showing invitation notification: $e');
    }
  }

  /// 通知被点击时的回调
  void _onNotificationTapped(NotificationResponse response) {
    // 这里可以处理通知点击事件
    print('Invitation notification tapped: ${response.payload}');
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