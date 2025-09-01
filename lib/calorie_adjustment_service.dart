import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'refresh_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CalorieAdjustmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 获取今天的日期字符串
  String _getTodayDate() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  /// 获取指定天数前的日期字符串
  String _getDateBefore(int days) {
    return DateFormat('yyyy-MM-dd').format(
      DateTime.now().subtract(Duration(days: days))
    );
  }

  /// 生成新的调整ID
  Future<String> _generateAdjustID() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('CalorieAdjustment')
          .get();

      if (snapshot.docs.isEmpty) {
        return 'A00001';
      }

      // 在内存中排序，找到最大的AdjustID
      final adjustIds = snapshot.docs
          .map((doc) {
            final data = doc.data();
            if (data != null && data is Map<String, dynamic>) {
              return data['AdjustID'] as String?;
            }
            return null;
          })
          .where((id) => id != null)
          .cast<String>()
          .toList();
      
      if (adjustIds.isEmpty) {
        return 'A00001';
      }
      
      adjustIds.sort((a, b) => b.compareTo(a)); // 降序
      String lastAdjustID = adjustIds.first;
      int lastNumber = int.parse(lastAdjustID.substring(1));
      int newNumber = lastNumber + 1;
      return 'A${newNumber.toString().padLeft(5, '0')}';
    } catch (e) {
      print('Error generating adjust ID: $e');
      return 'A00001';
    }
  }

  /// 从DOB计算年龄
  int _calculateAge(dynamic dob) {
    if (dob == null) return 25; // 默认年龄
    
    DateTime birthDate;
    if (dob is Timestamp) {
      birthDate = dob.toDate();
    } else if (dob is String) {
      birthDate = DateTime.parse(dob);
    } else {
      return 25; // 默认年龄
    }
    
    DateTime now = DateTime.now();
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month || 
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  /// 获取活动水平系数
  double _getActivityMultiplier(String activityLevel) {
    switch (activityLevel.toLowerCase()) {
      case 'sedentary':
        return 1.2; // 久坐（很少或没有运动）
      case 'light':
        return 1.375; // 轻度活跃（每周1-3天轻度运动）
      case 'moderate':
        return 1.55; // 中度活跃（每周3-5天中度运动）
      case 'very':
        return 1.725; // 非常活跃（每周6-7天剧烈运动）
      case 'super':
        return 1.9; // 超级活跃（剧烈运动 + 体力工作）
      default:
        return 1.2; // 默认久坐
    }
  }

  /// 计算用户的基础代谢率(BMR)
  double _calculateBMR(Map<String, dynamic> userData) {
    double weight = (userData['Weight'] ?? 70.0).toDouble();
    int height = userData['Height'] ?? 170;
    String gender = userData['Gender'] ?? 'male';
    
    // 从DOB计算真实年龄
    int age = _calculateAge(userData['DOB']);
    
    // BMR计算（Mifflin-St Jeor方程）
    if (gender.toLowerCase() == 'male') {
      return (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      return (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }
  }

  /// 计算用户的每日总能量消耗(TDEE)
  double _calculateTDEE(Map<String, dynamic> userData) {
    double bmr = _calculateBMR(userData);
    String activityLevel = userData['ActivityLevel'] ?? 'sedentary';
    double activityMultiplier = _getActivityMultiplier(activityLevel);
    
    return bmr * activityMultiplier;
  }

  /// 获取用户过去N天的摄入量数据
  Future<List<Map<String, dynamic>>> _getUserIntakeHistory(String userId, int days) async {
    List<Map<String, dynamic>> intakeHistory = [];
    
    for (int i = 1; i <= days; i++) {
      String date = _getDateBefore(i);
      
      final logQuery = await _firestore
          .collection('LogMeal')
          .where('UserID', isEqualTo: userId)
          .where('LogDate', isEqualTo: date)
          .get();
      
      int totalCalories = 0;
      for (var doc in logQuery.docs) {
        final data = doc.data();
        if (data != null && data is Map<String, dynamic>) {
          totalCalories += (data['TotalCalories'] ?? 0) as int;
        }
      }
      
      intakeHistory.add({
        'date': date,
        'totalCalories': totalCalories,
        'logged': logQuery.docs.isNotEmpty,
      });
    }
    
    return intakeHistory.reversed.toList(); // 最新的在前
  }

  /// 获取用户的原始基准目标卡路里（用于每日调整计算）
  Future<double> _getBaseTargetCalories(String userId) async {
    // 总是从Target表获取原始目标，不使用调整后的值
    final targetQuery = await _firestore
        .collection('Target')
        .where('UserID', isEqualTo: userId)
        .get();
    
    if (targetQuery.docs.isNotEmpty) {
      final data = targetQuery.docs.first.data();
      if (data != null && data is Map<String, dynamic>) {
        return (data['TargetCalories'] ?? 2000.0).toDouble();
      }
    }
    
    return 2000.0; // 默认值
  }

  /// 获取用户当前生效的目标卡路里（显示用）
  Future<double> _getCurrentTargetCalories(String userId) async {
    // 首先检查今天是否有调整记录
    final today = DateTime.now();
    final todayStr = today.toIso8601String().split('T')[0];
    
    final todayAdjustmentQuery = await _firestore
        .collection('CalorieAdjustment')
        .where('UserID', isEqualTo: userId)
        .where('AdjustDate', isEqualTo: todayStr)
        .get();
    
    if (todayAdjustmentQuery.docs.isNotEmpty) {
      // 使用今天的调整目标
      final data = todayAdjustmentQuery.docs.first.data();
      print('Using today\'s adjustment: ${data['AdjustTargetCalories']}');
      return (data['AdjustTargetCalories']).toDouble();
    }
    
    // 如果今天没有调整，检查昨天是否有调整记录
    final yesterday = today.subtract(Duration(days: 1));
    final yesterdayStr = yesterday.toIso8601String().split('T')[0];
    
    final yesterdayAdjustmentQuery = await _firestore
        .collection('CalorieAdjustment')
        .where('UserID', isEqualTo: userId)
        .where('AdjustDate', isEqualTo: yesterdayStr)
        .get();
    
    if (yesterdayAdjustmentQuery.docs.isNotEmpty) {
      // 使用昨天的调整目标
      final data = yesterdayAdjustmentQuery.docs.first.data();
      print('Using yesterday\'s adjustment: ${data['AdjustTargetCalories']}');
      return (data['AdjustTargetCalories']).toDouble();
    }
    
    // 如果都没有调整，使用原始目标
    final baseTarget = await _getBaseTargetCalories(userId);
    print('Using base target: $baseTarget');
    return baseTarget;
  }

  /// 每日调整算法 - 添加重复检查
  Future<Map<String, dynamic>> performDailyAdjustment(String userId) async {
    try {
      // 首先检查今天是否已经进行过调整
      final hasAdjustedToday = await this.hasAdjustedToday(userId);
      if (hasAdjustedToday) {
        return {
          'success': false,
          'reason': 'Daily adjustment already performed today',
        };
      }

      // 获取用户数据
      final userQuery = await _firestore
          .collection('User')
          .where('UserID', isEqualTo: userId)
          .get();
      
      if (userQuery.docs.isEmpty) {
        throw Exception('User not found');
      }
      
      final userData = userQuery.docs.first.data();
      if (userData == null || userData is! Map<String, dynamic>) {
        throw Exception('User data is not in expected format');
      }
      
      // 获取昨天的摄入量
      final intakeHistory = await _getUserIntakeHistory(userId, 1);
      if (intakeHistory.isEmpty || !intakeHistory.first['logged']) {
        return {
          'success': false,
          'reason': 'No intake data available for yesterday',
        };
      }
      
      final yesterdayIntake = intakeHistory.first['totalCalories'] as int;
      final baseTarget = await _getBaseTargetCalories(userId); // 使用原始基准目标
      final currentDisplayTarget = await _getCurrentTargetCalories(userId); // 当前显示的目标
      final bmr = _calculateBMR(userData);
      final tdee = _calculateTDEE(userData);
      final goal = userData['Goal'] ?? 'maintain';
      final gender = userData['Gender'] ?? 'male';
      
      // 检查是否需要调整（基于目标类型，使用原始目标）
      bool shouldAdjust = _shouldAdjustBasedOnGoal(goal, yesterdayIntake, baseTarget);
      
      if (!shouldAdjust) {
        return {
          'success': false,
          'reason': 'No adjustment needed based on goal type and intake pattern',
          'currentTarget': currentDisplayTarget,
          'baseTarget': baseTarget,
        };
      }
      
      // 计算新目标：基于原始目标和昨天摄入量的差值
      double deviation = yesterdayIntake - baseTarget;
      double newTarget = baseTarget - deviation;
      
      print('=== Daily Adjustment Calculation ===');
      print('Base target (original): $baseTarget');
      print('Current display target: $currentDisplayTarget');
      print('Yesterday intake: $yesterdayIntake');
      print('Deviation from base: $deviation');
      print('New calculated target: $newTarget');
      
      // 应用基于目标的安全边界
      newTarget = _applySafetyBoundaries(newTarget, goal, bmr, tdee, gender);
      
      // 如果调整幅度太小，不进行调整
      if ((newTarget - baseTarget).abs() < 25) {
        return {
          'success': false,
          'reason': 'Adjustment too small',
          'currentTarget': currentDisplayTarget,
          'baseTarget': baseTarget,
        };
      }
      
      // 创建调整记录
      await _createAdjustmentRecord(
        userId: userId,
        previousTarget: baseTarget, // 记录原始基准目标
        newTarget: newTarget,
      );
      
      print('=== Daily Adjustment Complete ===');
      print('Saved to database: base=$baseTarget -> new=$newTarget');
      
      // 立即触发页面刷新，确保首页显示调整后的目标
      RefreshManagerHelper.refreshAfterDailyAdjustment();
      
      return {
        'success': true,
        'previousTarget': baseTarget, // 返回原始基准目标
        'newTarget': newTarget,
        'adjustment': newTarget - baseTarget, // 基于原始目标的调整量
        'reason': 'Daily adjustment based on yesterday\'s intake vs original target',
      };
      
    } catch (e) {
      print('Error in daily adjustment: $e');
      return {
        'success': false,
        'reason': 'Error: $e',
      };
    }
  }

  /// 检查是否需要基于目标类型进行调整
  bool _shouldAdjustBasedOnGoal(String goal, int intake, double target) {
    switch (goal.toLowerCase()) {
      case 'gain':
        // 增重目标：只有摄入低于目标时才调整
        return intake < target;
      case 'loss':
        // 减重目标：只有摄入高于目标时才调整
        return intake > target;
      case 'maintain':
      default:
        // 维持目标：总是调整
        return true;
    }
  }

  /// 应用基于目标的安全边界
  double _applySafetyBoundaries(double newTarget, String goal, double bmr, double tdee, String gender) {
    double minCalories;
    double maxCalories;
    
    switch (goal.toLowerCase()) {
      case 'gain':
        // 增重目标：最大 = TDEE + 500
        minCalories = 0; // 无下限限制
        maxCalories = tdee + 500;
        break;
      case 'loss':
        // 减重目标：最小 = max(BMR, 1200女性/1500男性)
        int genderMinimum = gender.toLowerCase() == 'female' ? 1200 : 1500;
        minCalories = [bmr, genderMinimum.toDouble()].reduce((a, b) => a > b ? a : b);
        maxCalories = double.infinity; // 无上限限制
        break;
      case 'maintain':
      default:
        // 维持目标：应用两个限制
        int genderMinimum = gender.toLowerCase() == 'female' ? 1200 : 1500;
        minCalories = [bmr, genderMinimum.toDouble()].reduce((a, b) => a > b ? a : b);
        maxCalories = tdee + 500;
        break;
    }
    
    return newTarget.clamp(minCalories, maxCalories);
  }


  /// 创建调整记录
  Future<void> _createAdjustmentRecord({
    required String userId,
    required double previousTarget,
    required double newTarget,
  }) async {
    // 创建新的调整记录
    final adjustId = await _generateAdjustID();
    await _firestore.collection('CalorieAdjustment').add({
      'AdjustID': adjustId,
      'UserID': userId,
      'AdjustDate': _getTodayDate(),
      'PreviousTargetCalories': previousTarget.round(),
      'AdjustTargetCalories': newTarget.round(),
    });
  }

  /// 获取用户的调整历史
  Future<List<Map<String, dynamic>>> getAdjustmentHistory(String userId, {int limit = 10}) async {
    try {
      final query = await _firestore
          .collection('CalorieAdjustment')
          .where('UserID', isEqualTo: userId)
          .get();
      
      // 在内存中排序和限制，避免需要复合索引
      final docs = query.docs.map((doc) {
        final data = doc.data();
        if (data != null && data is Map<String, dynamic>) {
          return {
            'id': doc.id,
            ...data,
          };
        }
        return null;
      }).where((doc) => doc != null).cast<Map<String, dynamic>>().toList();
      
      // 按日期排序（降序）
      docs.sort((a, b) {
        final dateA = a['AdjustDate'] ?? '';
        final dateB = b['AdjustDate'] ?? '';
        return dateB.compareTo(dateA); // 降序
      });
      
      // 限制结果数量
      if (docs.length > limit) {
        return docs.take(limit).toList();
      }
      
      return docs;
    } catch (e) {
      print('Error getting adjustment history: $e');
      return [];
    }
  }

  /// 手动触发调整 - 已禁用
  Future<Map<String, dynamic>> triggerManualAdjustment(String userId, String type) async {
    return {
      'success': false,
      'reason': 'Manual adjustment is disabled. Only automatic daily adjustment is available.',
    };
  }

  /// 获取当前有效的目标卡路里（供其他服务使用）
  Future<int> getCurrentActiveTargetCalories(String userId) async {
    final target = await _getCurrentTargetCalories(userId);
    return target.round();
  }

  /// 获取用户的TDEE（供其他服务使用）
  Future<double> getUserTDEE(String userId) async {
    try {
      final userQuery = await _firestore
          .collection('User')
          .where('UserID', isEqualTo: userId)
          .get();
      
      if (userQuery.docs.isEmpty) {
        throw Exception('User not found');
      }
      
      final userData = userQuery.docs.first.data();
      if (userData == null) {
        throw Exception('User data is null');
      }
      
      // 确保 userData 是正确的类型
      if (userData is! Map<String, dynamic>) {
        throw Exception('User data is not in expected format');
      }
      
      return _calculateTDEE(userData);
    } catch (e) {
      print('Error getting user TDEE: $e');
      return 2000.0; // 默认值
    }
  }

  /// 获取用户的BMR（供其他服务使用）
  Future<double> getUserBMR(String userId) async {
    try {
      final userQuery = await _firestore
          .collection('User')
          .where('UserID', isEqualTo: userId)
          .get();
      
      if (userQuery.docs.isEmpty) {
        throw Exception('User not found');
      }
      
      final userData = userQuery.docs.first.data();
      if (userData == null) {
        throw Exception('User data is null');
      }
      
      // 确保 userData 是正确的类型
      if (userData is! Map<String, dynamic>) {
        throw Exception('User data is not in expected format');
      }
      
      return _calculateBMR(userData);
    } catch (e) {
      print('Error getting user BMR: $e');
      return 1500.0; // 默认值
    }
  }

  /// 自动调整检查 - 只执行每日调整
  Future<Map<String, dynamic>> performAutoAdjustment(String userId) async {
    try {
      // 只执行每日调整
      final dailyResult = await performDailyAdjustment(userId);
      
      // 返回调整结果
      return {
        'success': dailyResult['success'],
        'daily': dailyResult,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('Error in auto adjustment: $e');
      return {
        'success': false,
        'reason': 'Error: $e',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// 检查用户是否启用了自动调整
  Future<bool> isAutoAdjustmentEnabled(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'auto_adjustment_enabled_$userId';
      return prefs.getBool(key) ?? true; // 默认启用
    } catch (e) {
      print('Error checking auto adjustment setting: $e');
      return true; // 错误时默认启用
    }
  }

  /// 保存自动调整设置
  Future<void> setAutoAdjustmentEnabled(String userId, bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'auto_adjustment_enabled_$userId';
      await prefs.setBool(key, enabled);
      print('Auto adjustment ${enabled ? 'enabled' : 'disabled'} for user $userId');
    } catch (e) {
      print('Error saving auto adjustment setting: $e');
    }
  }

  /// 检查今天是否已经进行过调整
  Future<bool> hasAdjustedToday(String userId) async {
    try {
      final today = _getTodayDate();
      
      final adjustmentQuery = await _firestore
          .collection('CalorieAdjustment')
          .where('UserID', isEqualTo: userId)
          .where('AdjustDate', isEqualTo: today)
          .get();
      
      return adjustmentQuery.docs.isNotEmpty;
    } catch (e) {
      print('Error checking today\'s adjustment: $e');
      return false;
    }
  }

  /// 检查用户在指定日期是否已经进行过调整
  Future<bool> hasAdjustedOnDate(String userId, String date) async {
    try {
      final query = await _firestore
          .collection('CalorieAdjustment')
          .where('UserID', isEqualTo: userId)
          .where('AdjustDate', isEqualTo: date)
          .get();
      
      return query.docs.isNotEmpty;
    } catch (e) {
      print('Error checking adjustment for $date: $e');
      return false;
    }
  }

  /// 为指定日期执行调整（用于补偿错过的调整）
  Future<Map<String, dynamic>> performDailyAdjustmentForDate(String userId, String date) async {
    try {
      print('=== Performing adjustment for date: $date ===');
      
      // 检查指定日期是否已经调整过
      final hasAdjusted = await hasAdjustedOnDate(userId, date);
      if (hasAdjusted) {
        return {
          'success': false,
          'reason': 'Already adjusted for $date',
        };
      }

      // 获取用户数据
      final userQuery = await _firestore
          .collection('User')
          .where('UserID', isEqualTo: userId)
          .get();
      
      if (userQuery.docs.isEmpty) {
        throw Exception('User not found');
      }
      
      final userData = userQuery.docs.first.data();
      if (userData == null || userData is! Map<String, dynamic>) {
        throw Exception('User data is not in expected format');
      }
      
      // 获取指定日期前一天的摄入量
      final targetDate = DateTime.parse(date);
      final dayBefore = targetDate.subtract(Duration(days: 1));
      final dayBeforeStr = dayBefore.toIso8601String().split('T')[0];
      
      final intakeHistory = await _getUserIntakeHistoryForDate(userId, dayBeforeStr);
      if (intakeHistory.isEmpty || !intakeHistory.first['logged']) {
        return {
          'success': false,
          'reason': 'No intake data available for $dayBeforeStr',
        };
      }
      
      final intakeAmount = intakeHistory.first['totalCalories'] as int;
      final baseTarget = await _getBaseTargetCalories(userId);
      final bmr = _calculateBMR(userData);
      final tdee = _calculateTDEE(userData);
      final goal = userData['Goal'] ?? 'maintain';
      final gender = userData['Gender'] ?? 'male';
      
      // 检查是否需要调整
      bool shouldAdjust = _shouldAdjustBasedOnGoal(goal, intakeAmount, baseTarget);
      
      if (!shouldAdjust) {
        return {
          'success': false,
          'reason': 'No adjustment needed for $date',
        };
      }
      
      // 计算新目标
      double deviation = intakeAmount - baseTarget;
      double newTarget = baseTarget - deviation;
      
      // 应用安全边界
      newTarget = _applySafetyBoundaries(newTarget, goal, bmr, tdee, gender);
      
      // 检查调整幅度
      if ((newTarget - baseTarget).abs() < 25) {
        return {
          'success': false,
          'reason': 'Adjustment too small for $date',
        };
      }
      
      // 创建指定日期的调整记录
      await _createAdjustmentRecordForDate(
        userId: userId,
        previousTarget: baseTarget,
        newTarget: newTarget,
        date: date,
      );
      
      print('=== Adjustment completed for $date ===');
      
      return {
        'success': true,
        'previousTarget': baseTarget,
        'newTarget': newTarget,
        'adjustment': newTarget - baseTarget,
        'reason': 'Retroactive adjustment for $date',
        'date': date,
      };
      
    } catch (e) {
      print('Error in adjustment for $date: $e');
      return {
        'success': false,
        'reason': 'Error: $e',
      };
    }
  }

  /// 获取指定日期的摄入量数据
  Future<List<Map<String, dynamic>>> _getUserIntakeHistoryForDate(String userId, String date) async {
    final query = await _firestore
        .collection('FoodLog')
        .where('UserID', isEqualTo: userId)
        .where('Date', isEqualTo: date)
        .get();
    
    if (query.docs.isEmpty) {
      return [{
        'date': date,
        'totalCalories': 0,
        'logged': false,
      }];
    }
    
    int totalCalories = 0;
    for (var doc in query.docs) {
      final data = doc.data();
      if (data != null && data is Map<String, dynamic>) {
        totalCalories += ((data['Calories'] as num?) ?? 0).toInt();
      }
    }
    
    return [{
      'date': date,
      'totalCalories': totalCalories,
      'logged': totalCalories > 0,
    }];
  }

  /// 为指定日期创建调整记录
  Future<void> _createAdjustmentRecordForDate({
    required String userId,
    required double previousTarget,
    required double newTarget,
    required String date,
  }) async {
    await _firestore.collection('CalorieAdjustment').add({
      'UserID': userId,
      'PreviousTargetCalories': previousTarget,
      'AdjustTargetCalories': newTarget,
      'AdjustDate': date,
    });
    
    print('Created adjustment record for $date: $previousTarget -> $newTarget');
  }

} 

















