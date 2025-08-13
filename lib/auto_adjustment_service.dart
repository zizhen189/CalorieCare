import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'calorie_adjustment_service.dart';
import 'notification_service.dart';

class AutoAdjustmentService {
  static final AutoAdjustmentService _instance = AutoAdjustmentService._internal();
  factory AutoAdjustmentService() => _instance;
  AutoAdjustmentService._internal();

  final CalorieAdjustmentService _adjustmentService = CalorieAdjustmentService();
  final NotificationService _notificationService = NotificationService();
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

    // 计算到下一个午夜12点的时间
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = nextMidnight.difference(now);

    print('Auto adjustment scheduled for ${nextMidnight.toIso8601String()}');
    print('Time until next execution: ${timeUntilMidnight.inHours}h ${timeUntilMidnight.inMinutes % 60}m');

    // 设置每日定时器
    _dailyTimer = Timer(timeUntilMidnight, () {
      _executeDailyAutoAdjustment();
    });
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
} 


