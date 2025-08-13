import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'goal_achievement_service.dart';

class WeightService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoalAchievementService _goalService = GoalAchievementService();

  // 检查今天是否已经记录体重
  Future<bool> hasRecordedWeightToday(String userId) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      final query = await _firestore
          .collection('WeightRecord')
          .where('UserID', isEqualTo: userId)
          .where('RecordDate', isEqualTo: today)
          .limit(1)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      print('Error checking weight record: $e');
      return false;
    }
  }

  // 记录体重并检查目标达成
  Future<Map<String, dynamic>> recordWeight(String userId, double weight) async {
    try {
      print('=== Recording Weight ===');
      print('User ID: $userId');
      print('Weight: $weight');
      
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      await _firestore.collection('WeightRecord').add({
        'UserID': userId,
        'Weight': weight,
        'RecordDate': today,
        'RecordTime': FieldValue.serverTimestamp(),
      });

      print('Weight recorded successfully');

      // Check for goal achievement
      final goalAchieved = await _goalService.checkAndProcessGoalAchievement(userId, weight);
      print('Goal achievement result: $goalAchieved');
      
      return {
        'success': true,
        'goalAchieved': goalAchieved,
        'weight': weight,
      };
    } catch (e) {
      print('Error recording weight: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // 为特定日期记录体重并检查目标达成
  Future<Map<String, dynamic>> recordWeightForDate(String userId, double weight, String dateStr) async {
    try {
      await _firestore.collection('WeightRecord').add({
        'UserID': userId,
        'Weight': weight,
        'RecordDate': dateStr,
        'RecordTime': FieldValue.serverTimestamp(),
      });

      // Only check goal achievement if recording for today
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      bool goalAchieved = false;
      
      if (dateStr == today) {
        goalAchieved = await _goalService.checkAndProcessGoalAchievement(userId, weight);
      }
      
      return {
        'success': true,
        'goalAchieved': goalAchieved,
        'weight': weight,
      };
    } catch (e) {
      print('Error recording weight for date: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // 获取用户的体重记录历史
  Future<List<Map<String, dynamic>>> getWeightHistory(String userId, {int limit = 30}) async {
    try {
      final query = await _firestore
          .collection('WeightRecord')
          .where('UserID', isEqualTo: userId)
          .get();

      // 在客户端排序和限制
      final sortedDocs = query.docs.toList()
        ..sort((a, b) {
          final dateA = a.data()['RecordDate'] as String? ?? '';
          final dateB = b.data()['RecordDate'] as String? ?? '';
          return dateB.compareTo(dateA); // 降序排列
        });

      final limitedDocs = sortedDocs.take(limit).toList();

      return limitedDocs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'weight': data['Weight'] ?? 0.0,
          'date': data['RecordDate'] ?? '',
          'timestamp': data['RecordTime'],
        };
      }).toList();
    } catch (e) {
      print('Error getting weight history: $e');
      return [];
    }
  }

  // 获取最新的体重记录
  Future<Map<String, dynamic>?> getLatestWeight(String userId) async {
    try {
      final query = await _firestore
          .collection('WeightRecord')
          .where('UserID', isEqualTo: userId)
          .get();

      if (query.docs.isNotEmpty) {
        // 在客户端找到最新的记录
        final latestDoc = query.docs.reduce((a, b) {
          final dateA = a.data()['RecordDate'] as String? ?? '';
          final dateB = b.data()['RecordDate'] as String? ?? '';
          return dateA.compareTo(dateB) > 0 ? a : b;
        });

        final data = latestDoc.data();
        return {
          'id': latestDoc.id,
          'weight': data['Weight'] ?? 0.0,
          'date': data['RecordDate'] ?? '',
          'timestamp': data['RecordTime'],
        };
      }
      return null;
    } catch (e) {
      print('Error getting latest weight: $e');
      return null;
    }
  }

  // 获取指定日期范围的体重记录
  Future<List<Map<String, dynamic>>> getWeightRecordsByDateRange(
    String userId, 
    DateTime startDate, 
    DateTime endDate
  ) async {
    try {
      // 获取所有用户的体重记录，然后在客户端过滤和排序
      final query = await _firestore
          .collection('WeightRecord')
          .where('UserID', isEqualTo: userId)
          .get();

      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      // 在客户端过滤日期范围
      final filteredDocs = query.docs.where((doc) {
        final recordDate = doc.data()['RecordDate'] as String?;
        if (recordDate == null) return false;
        return recordDate.compareTo(startDateStr) >= 0 && recordDate.compareTo(endDateStr) <= 0;
      }).toList();

      // 在客户端按日期排序（升序）
      filteredDocs.sort((a, b) {
        final dateA = a.data()['RecordDate'] as String? ?? '';
        final dateB = b.data()['RecordDate'] as String? ?? '';
        return dateA.compareTo(dateB);
      });

      return filteredDocs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'weight': data['Weight'] ?? 0.0,
          'date': data['RecordDate'] ?? '',
          'timestamp': data['RecordTime'],
        };
      }).toList();
    } catch (e) {
      print('Error getting weight records by date range: $e');
      return [];
    }
  }

  // 更新体重记录
  Future<Map<String, dynamic>> updateWeightRecord(String userId, String oldDate, double newWeight, String newDate) async {
    try {
      print('=== Updating Weight Record ===');
      print('User ID: $userId');
      print('Old Date: $oldDate');
      print('New Weight: $newWeight');
      print('New Date: $newDate');
      
      // Query for the existing record
      final query = await _firestore
          .collection('WeightRecord')
          .where('UserID', isEqualTo: userId)
          .where('RecordDate', isEqualTo: oldDate)
          .get();

      if (query.docs.isNotEmpty) {
        // 更新第一个匹配的记录
        final docRef = query.docs.first.reference;
        await docRef.update({
          'Weight': newWeight,
          'RecordDate': newDate,
          'RecordTime': FieldValue.serverTimestamp(),
        });
        print('Weight record updated successfully');
      } else {
        // 如果找不到记录，创建一个新的
        print('Record not found, creating new record');
        await recordWeightForDate(userId, newWeight, newDate);
        return {
          'success': true,
          'goalAchieved': false, // 新记录的目标达成检查已在recordWeightForDate中处理
        };
      }

      // Check for goal achievement after updating weight
      final goalAchieved = await _goalService.checkAndProcessGoalAchievement(userId, newWeight);
      print('Goal achievement result: $goalAchieved');
      
      return {
        'success': true,
        'goalAchieved': goalAchieved,
        'weight': newWeight,
      };
    } catch (e) {
      print('Error updating weight record: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
} 
