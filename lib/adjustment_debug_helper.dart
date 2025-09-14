import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caloriecare/calorie_adjustment_service.dart';

class AdjustmentDebugHelper {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CalorieAdjustmentService _adjustmentService = CalorieAdjustmentService();

  /// 调试当前调整状态
  Future<Map<String, dynamic>> debugCurrentAdjustmentState(String userId) async {
    try {
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final yesterday = now.subtract(Duration(days: 1));
      final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      final dayBeforeYesterday = now.subtract(Duration(days: 2));
      final dayBeforeYesterdayStr = '${dayBeforeYesterday.year}-${dayBeforeYesterday.month.toString().padLeft(2, '0')}-${dayBeforeYesterday.day.toString().padLeft(2, '0')}';

      print('=== ADJUSTMENT DEBUG INFO ===');
      print('Current time: ${now.toString()}');
      print('Today: $today');
      print('Yesterday: $yesterdayStr');
      print('Day before yesterday: $dayBeforeYesterdayStr');

      // 检查今天的调整记录
      final todayAdjustments = await _firestore
          .collection('CalorieAdjustment')
          .where('UserID', isEqualTo: userId)
          .where('AdjustDate', isEqualTo: today)
          .get();

      // 检查昨天的调整记录
      final yesterdayAdjustments = await _firestore
          .collection('CalorieAdjustment')
          .where('UserID', isEqualTo: userId)
          .where('AdjustDate', isEqualTo: yesterdayStr)
          .get();

      // 检查前天的调整记录
      final dayBeforeAdjustments = await _firestore
          .collection('CalorieAdjustment')
          .where('UserID', isEqualTo: userId)
          .where('AdjustDate', isEqualTo: dayBeforeYesterdayStr)
          .get();

      // 检查今天的摄入记录
      final todayIntake = await _firestore
          .collection('LogMeal')
          .where('UserID', isEqualTo: userId)
          .where('LogDate', isEqualTo: today)
          .get();

      // 检查昨天的摄入记录
      final yesterdayIntake = await _firestore
          .collection('LogMeal')
          .where('UserID', isEqualTo: userId)
          .where('LogDate', isEqualTo: yesterdayStr)
          .get();

      // 检查前天的摄入记录
      final dayBeforeIntake = await _firestore
          .collection('LogMeal')
          .where('UserID', isEqualTo: userId)
          .where('LogDate', isEqualTo: dayBeforeYesterdayStr)
          .get();

      print('Today adjustments: ${todayAdjustments.docs.length}');
      for (var doc in todayAdjustments.docs) {
        final data = doc.data();
        print('  - ${data['AdjustDate']}: ${data['PreviousTargetCalories']} -> ${data['AdjustTargetCalories']}');
      }

      print('Yesterday adjustments: ${yesterdayAdjustments.docs.length}');
      for (var doc in yesterdayAdjustments.docs) {
        final data = doc.data();
        print('  - ${data['AdjustDate']}: ${data['PreviousTargetCalories']} -> ${data['AdjustTargetCalories']}');
      }

      print('Day before yesterday adjustments: ${dayBeforeAdjustments.docs.length}');
      for (var doc in dayBeforeAdjustments.docs) {
        final data = doc.data();
        print('  - ${data['AdjustDate']}: ${data['PreviousTargetCalories']} -> ${data['AdjustTargetCalories']}');
      }

      // 计算摄入量
      int todayCalories = 0;
      for (var doc in todayIntake.docs) {
        todayCalories += (doc.data()['TotalCalories'] ?? 0) as int;
      }

      int yesterdayCalories = 0;
      for (var doc in yesterdayIntake.docs) {
        yesterdayCalories += (doc.data()['TotalCalories'] ?? 0) as int;
      }

      int dayBeforeCalories = 0;
      for (var doc in dayBeforeIntake.docs) {
        dayBeforeCalories += (doc.data()['TotalCalories'] ?? 0) as int;
      }

      print('Today intake: $todayCalories calories');
      print('Yesterday intake: $yesterdayCalories calories');
      print('Day before yesterday intake: $dayBeforeCalories calories');

      // 检查hasAdjustedToday的结果
      final hasAdjustedToday = await _adjustmentService.hasAdjustedToday(userId);
      print('hasAdjustedToday result: $hasAdjustedToday');

      // 获取当前活跃目标
      final currentTarget = await _adjustmentService.getCurrentActiveTargetCalories(userId);
      print('Current active target: $currentTarget');

      print('=== END DEBUG INFO ===');

      return {
        'currentTime': now.toString(),
        'today': today,
        'yesterday': yesterdayStr,
        'dayBeforeYesterday': dayBeforeYesterdayStr,
        'todayAdjustments': todayAdjustments.docs.length,
        'yesterdayAdjustments': yesterdayAdjustments.docs.length,
        'dayBeforeAdjustments': dayBeforeAdjustments.docs.length,
        'todayIntake': todayCalories,
        'yesterdayIntake': yesterdayCalories,
        'dayBeforeIntake': dayBeforeCalories,
        'hasAdjustedToday': hasAdjustedToday,
        'currentTarget': currentTarget,
      };
    } catch (e) {
      print('Error in debug: $e');
      return {'error': e.toString()};
    }
  }

  /// 清理错误的调整记录
  Future<void> cleanupIncorrectAdjustments(String userId) async {
    try {
      print('=== CLEANING UP INCORRECT ADJUSTMENTS ===');
      
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final yesterday = now.subtract(Duration(days: 1));
      final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      // 获取所有调整记录
      final allAdjustments = await _firestore
          .collection('CalorieAdjustment')
          .where('UserID', isEqualTo: userId)
          .orderBy('AdjustDate', descending: true)
          .limit(10)
          .get();

      print('Found ${allAdjustments.docs.length} adjustment records:');
      for (var doc in allAdjustments.docs) {
        final data = doc.data();
        print('  - ${data['AdjustDate']}: ${data['PreviousTargetCalories']} -> ${data['AdjustTargetCalories']}');
      }

      // 这里可以添加清理逻辑，比如删除错误的记录
      // 但为了安全起见，我们先只显示信息
      
      print('=== END CLEANUP ===');
    } catch (e) {
      print('Error in cleanup: $e');
    }
  }
}
