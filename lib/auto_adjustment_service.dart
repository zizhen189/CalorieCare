import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'calorie_adjustment_service.dart';
import 'notification_service.dart';
import 'refresh_manager.dart';

class AutoAdjustmentService {
  static final AutoAdjustmentService _instance = AutoAdjustmentService._internal();
  factory AutoAdjustmentService() => _instance;
  AutoAdjustmentService._internal();

  final CalorieAdjustmentService _adjustmentService = CalorieAdjustmentService();
  final NotificationService _notificationService = NotificationService();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  Timer? _dailyTimer;
  String? _currentUserId;

    /// 启动自动调整服务（添加重复启动检查）
  Future<void> startAutoAdjustment(String userId) async {
    // 如果已经在运行且是同一个用户，直接返回
    if (_dailyTimer != null && _currentUserId == userId) {
      print('Auto adjustment already running for user $userId');
      return;
    }
    
    // 停止之前的定时器
    stopAutoAdjustment();
    
    _currentUserId = userId;
    
    // 初始化通知服务
    await _notificationService.initialize();
    
    // 检查是否启用自动调整
    final isEnabled = await _adjustmentService.isAutoAdjustmentEnabled(userId);
    if (!isEnabled) {
      print('Auto adjustment is disabled for user $userId');
      return;
    }

    // 【关键】app启动时检查是否有错过的调整
    await _checkMissedAdjustmentOnStartup(userId);

    // 计算到下一个午夜12点的时间
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = nextMidnight.difference(now);

    print('Auto adjustment scheduled for ${nextMidnight.toIso8601String()}');
    print('Time until next execution: ${timeUntilMidnight.inHours}h ${timeUntilMidnight.inMinutes % 60}m');

    // 设置每日定时器（app内）
    _dailyTimer = Timer(timeUntilMidnight, () {
      _executeDailyAutoAdjustment();
    });
    
    // 同时安排本地通知作为备用（app关闭时的兜底方案）
    await _scheduleLocalNotificationBackup(userId, nextMidnight);
  }

  /// 停止自动调整服务
  void stopAutoAdjustment() {
    _dailyTimer?.cancel();
    _dailyTimer = null;
    _currentUserId = null;
    print('Auto adjustment service stopped');
  }

  /// 执行每日自动调整 - 添加额外的重复检查
  Future<void> _executeDailyAutoAdjustment() async {
    if (_currentUserId == null) return;

    print('Executing daily auto adjustment for user $_currentUserId');
    
    try {
      // 检查自动调整是否仍然启用
      final isEnabled = await _adjustmentService.isAutoAdjustmentEnabled(_currentUserId!);
      if (!isEnabled) {
        print('Auto adjustment is disabled for user $_currentUserId, stopping service');
        stopAutoAdjustment();
        return;
      }
      
      // 双重检查：确保今天还没有进行过调整
      final hasAdjusted = await _adjustmentService.hasAdjustedToday(_currentUserId!);
      if (hasAdjusted) {
        print('Daily adjustment already completed today, skipping...');
        // 重新调度下一次执行（24小时后）
        _scheduleDailyTimer();
        return;
      }
      
      final result = await _adjustmentService.performDailyAdjustment(_currentUserId!);
      
      if (result['success']) {
        print('Auto adjustment completed successfully');
        print('Daily result: ${result}');
        
        // 发送通知给用户
        await _notificationService.showAutoAdjustmentNotification(result: {'daily': result});
        
        // 触发页面刷新
        RefreshManagerHelper.refreshAfterDailyAdjustment();
      } else {
        print('Auto adjustment completed with no changes needed: ${result['reason']}');
      }
    } catch (e) {
      print('Error executing auto adjustment: $e');
    }

    // 重新调度下一次执行（24小时后）
    _scheduleDailyTimer();
  }

  /// 调度每日定时器
  void _scheduleDailyTimer() {
    _dailyTimer = Timer(const Duration(days: 1), () {
      _executeDailyAutoAdjustment();
    });
  }



  /// 立即执行一次自动调整（用于测试）
  Future<Map<String, dynamic>> executeNow(String userId) async {
    print('Executing immediate auto adjustment for user $userId');
    final result = await _adjustmentService.performDailyAdjustment(userId);
    
    if (result['success']) {
      print('Auto adjustment completed successfully');
      print('Daily result: ${result}');
      
      // 发送通知给用户
      await _notificationService.showAutoAdjustmentNotification(result: {'daily': result});
    } else {
      print('Auto adjustment completed with no changes needed: ${result['reason']}');
    }
    
    return result;
  }

  /// 调试方法：检查自动调整状态
  Future<Map<String, dynamic>> debugAutoAdjustmentStatus(String userId) async {
    try {
      final isEnabled = await _adjustmentService.isAutoAdjustmentEnabled(userId);
      final hasAdjustedToday = await _adjustmentService.hasAdjustedToday(userId);
      final isRunning = this.isRunning;
      final currentUserId = this.currentUserId;
      
      print('=== Auto Adjustment Debug Info ===');
      print('User ID: $userId');
      print('Is Enabled: $isEnabled');
      print('Has Adjusted Today: $hasAdjustedToday');
      print('Service Running: $isRunning');
      print('Current User ID: $currentUserId');
      print('================================');
      
      return {
        'isEnabled': isEnabled,
        'hasAdjustedToday': hasAdjustedToday,
        'isRunning': isRunning,
        'currentUserId': currentUserId,
      };
    } catch (e) {
      print('Error in debug status: $e');
      return {
        'error': e.toString(),
      };
    }
  }

  /// 检查服务状态
  bool get isRunning => _dailyTimer != null;
  
  String? get currentUserId => _currentUserId;

  /// 【关键方法】app启动时检查错过的调整
  Future<void> _checkMissedAdjustmentOnStartup(String userId) async {
    try {
      print('=== Checking for missed adjustments on startup ===');
      
      final now = DateTime.now();
      final today = now.toIso8601String().split('T')[0];
      
      // 如果当前时间已经超过今天的12点，且今天还没有调整过，说明错过了
      if (now.hour >= 0) { // 00:00之后就算是新的一天
        final hasAdjustedToday = await _adjustmentService.hasAdjustedToday(userId);
        
        if (!hasAdjustedToday) {
          print('Found missed adjustment for today: $today');
          print('Current time: ${now.toIso8601String()}');
          
          // 立即执行错过的调整
          final result = await _adjustmentService.performDailyAdjustment(userId);
          
          if (result['success']) {
            print('Missed adjustment completed successfully: ${result}');
            
            // 发送补偿调整通知
            await _notificationService.showAutoAdjustmentNotification(
              result: {'daily': result},
              isCatchUp: true,
            );
            
            // 触发页面刷新
            RefreshManagerHelper.refreshAfterMissedAdjustment();
          } else {
            print('Missed adjustment not needed: ${result['reason']}');
          }
        } else {
          print('Today\'s adjustment already completed');
        }
      }
    } catch (e) {
      print('Error checking missed adjustments: $e');
    }
  }

  /// 安排本地通知作为备用方案（app关闭时的兜底机制）
  Future<void> _scheduleLocalNotificationBackup(String userId, DateTime scheduledTime) async {
    try {
      // 取消之前的通知
      await _localNotifications.cancel(999); // 使用固定ID
      
      const AndroidNotificationDetails androidNotificationDetails = AndroidNotificationDetails(
        'auto_adjustment_channel',
        'Auto Adjustment Reminders',
        channelDescription: 'Notifications to remind about calorie adjustments',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );
      
      const DarwinNotificationDetails iOSNotificationDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: iOSNotificationDetails,
      );
      
      // 转换为TZDateTime并安排通知在12点显示
      final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);
      
      await _localNotifications.zonedSchedule(
        999, // 固定ID
        'CalorieCare Auto Adjustment',
        'Time for your daily calorie adjustment! Open the app to apply changes.',
        tzScheduledTime,
        notificationDetails,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      
      print('Scheduled backup notification for ${scheduledTime.toIso8601String()}');
    } catch (e) {
      print('Error scheduling backup notification: $e');
    }
  }

  /// 处理本地通知点击（当用户点击通知时触发调整）
  Future<void> handleNotificationTap(String userId) async {
    try {
      print('Auto adjustment notification tapped, executing adjustment...');
      
      final result = await _adjustmentService.performDailyAdjustment(userId);
      
      if (result['success']) {
        print('Notification-triggered adjustment completed: ${result}');
        
        // 显示成功通知
        await _notificationService.showAutoAdjustmentNotification(
          result: {'daily': result},
          isManualTrigger: true,
        );
      } else {
        print('Notification-triggered adjustment not needed: ${result['reason']}');
      }
    } catch (e) {
      print('Error handling notification tap: $e');
    }
  }
} 


