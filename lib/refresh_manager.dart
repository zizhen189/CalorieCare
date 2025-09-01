import 'dart:async';
import 'package:flutter/material.dart';

/// 全局刷新管理器
/// 负责管理应用中各种数据的刷新通知
class RefreshManager {
  static final RefreshManager _instance = RefreshManager._internal();
  factory RefreshManager() => _instance;
  RefreshManager._internal();

  // 各种数据刷新的流控制器
  final StreamController<bool> _homePageController = StreamController<bool>.broadcast();
  final StreamController<bool> _calorieTargetController = StreamController<bool>.broadcast();
  final StreamController<bool> _supervisionController = StreamController<bool>.broadcast();
  final StreamController<bool> _streakController = StreamController<bool>.broadcast();
  final StreamController<bool> _progressController = StreamController<bool>.broadcast();
  final StreamController<bool> _weightController = StreamController<bool>.broadcast();

  // 流访问器
  Stream<bool> get homePageRefreshStream => _homePageController.stream;
  Stream<bool> get calorieTargetRefreshStream => _calorieTargetController.stream;
  Stream<bool> get supervisionRefreshStream => _supervisionController.stream;
  Stream<bool> get streakRefreshStream => _streakController.stream;
  Stream<bool> get progressRefreshStream => _progressController.stream;
  Stream<bool> get weightRefreshStream => _weightController.stream;

  /// 刷新首页数据
  void refreshHomePage({String? reason}) {
    print('🔄 RefreshManager: Refreshing home page${reason != null ? ' - $reason' : ''}');
    _homePageController.add(true);
  }

  /// 刷新卡路里目标数据
  void refreshCalorieTarget({String? reason}) {
    print('🔄 RefreshManager: Refreshing calorie target${reason != null ? ' - $reason' : ''}');
    _calorieTargetController.add(true);
  }

  /// 刷新supervision数据
  void refreshSupervision({String? reason}) {
    print('🔄 RefreshManager: Refreshing supervision${reason != null ? ' - $reason' : ''}');
    _supervisionController.add(true);
  }

  /// 刷新streak数据
  void refreshStreak({String? reason}) {
    print('🔄 RefreshManager: Refreshing streak${reason != null ? ' - $reason' : ''}');
    _streakController.add(true);
  }

  /// 刷新进度数据
  void refreshProgress({String? reason}) {
    print('🔄 RefreshManager: Refreshing progress${reason != null ? ' - $reason' : ''}');
    _progressController.add(true);
  }

  /// 刷新体重数据
  void refreshWeight({String? reason}) {
    print('🔄 RefreshManager: Refreshing weight${reason != null ? ' - $reason' : ''}');
    _weightController.add(true);
  }

  /// 全量刷新所有数据
  void refreshAll({String? reason}) {
    print('🔄 RefreshManager: Refreshing ALL data${reason != null ? ' - $reason' : ''}');
    refreshHomePage(reason: reason);
    refreshCalorieTarget(reason: reason);
    refreshSupervision(reason: reason);
    refreshStreak(reason: reason);
    refreshProgress(reason: reason);
    refreshWeight(reason: reason);
  }

  /// 针对特定操作的刷新组合
  
  /// missed adjustment后的刷新
  void refreshAfterMissedAdjustment() {
    print('🔄 RefreshManager: Handling missed adjustment refresh');
    refreshHomePage(reason: 'missed adjustment');
    refreshCalorieTarget(reason: 'missed adjustment');
    refreshProgress(reason: 'missed adjustment');
  }

  /// accept supervisor后的刷新
  void refreshAfterAcceptSupervisor() {
    print('🔄 RefreshManager: Handling accept supervisor refresh');
    refreshHomePage(reason: 'accept supervisor');
    refreshSupervision(reason: 'accept supervisor');
    refreshStreak(reason: 'accept supervisor');
  }

  /// 每日调整后的刷新
  void refreshAfterDailyAdjustment() {
    print('🔄 RefreshManager: Handling daily adjustment refresh');
    refreshHomePage(reason: 'daily adjustment');
    refreshCalorieTarget(reason: 'daily adjustment');
    refreshProgress(reason: 'daily adjustment');
  }

  /// log food后的刷新
  void refreshAfterLogFood() {
    print('🔄 RefreshManager: Handling log food refresh');
    refreshHomePage(reason: 'log food');
    refreshStreak(reason: 'log food');
    refreshProgress(reason: 'log food');
  }

  /// 体重记录后的刷新
  void refreshAfterWeightRecord() {
    print('🔄 RefreshManager: Handling weight record refresh');
    refreshHomePage(reason: 'weight record');
    refreshWeight(reason: 'weight record');
    refreshProgress(reason: 'weight record');
  }

  /// 目标达成后的刷新
  void refreshAfterGoalAchievement() {
    print('🔄 RefreshManager: Handling goal achievement refresh');
    refreshHomePage(reason: 'goal achievement');
    refreshCalorieTarget(reason: 'goal achievement');
    refreshProgress(reason: 'goal achievement');
    refreshWeight(reason: 'goal achievement');
  }

  /// edit profile后的刷新
  void refreshAfterEditProfile() {
    print('🔄 RefreshManager: Handling edit profile refresh');
    refreshHomePage(reason: 'edit profile');
    refreshCalorieTarget(reason: 'edit profile');
    refreshProgress(reason: 'edit profile');
    refreshWeight(reason: 'edit profile');
  }

  /// 清理资源
  void dispose() {
    _homePageController.close();
    _calorieTargetController.close();
    _supervisionController.close();
    _streakController.close();
    _progressController.close();
    _weightController.close();
  }
}

/// RefreshManager的便捷访问器
class RefreshManagerHelper {
  static RefreshManager get instance => RefreshManager();
  
  /// 快捷方法
  static void refreshHomePage({String? reason}) => instance.refreshHomePage(reason: reason);
  static void refreshAfterMissedAdjustment() => instance.refreshAfterMissedAdjustment();
  static void refreshAfterAcceptSupervisor() => instance.refreshAfterAcceptSupervisor();
  static void refreshAfterDailyAdjustment() => instance.refreshAfterDailyAdjustment();
  static void refreshAfterLogFood() => instance.refreshAfterLogFood();
  static void refreshAfterWeightRecord() => instance.refreshAfterWeightRecord();
  static void refreshAfterGoalAchievement() => instance.refreshAfterGoalAchievement();
  static void refreshAfterEditProfile() => instance.refreshAfterEditProfile();
  static void refreshAll({String? reason}) => instance.refreshAll(reason: reason);
}
