import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'goal_achievement_service.dart';

class WeightService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoalAchievementService _goalService = GoalAchievementService();

  /// Generate new WeightID
  Future<String> _generateWeightID() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('WeightRecord')
          .get();

      if (snapshot.docs.isEmpty) {
        return 'W00001';
      }

      // 在内存中排序，找到最大的WeightID
      final weightIds = snapshot.docs
          .map((doc) {
            final data = doc.data();
            if (data != null && data is Map<String, dynamic>) {
              return data['WeightID'] as String?;
            }
            return null;
          })
          .where((id) => id != null)
          .cast<String>()
          .toList();
      
      if (weightIds.isEmpty) {
        return 'W00001';
      }
      
      weightIds.sort((a, b) => b.compareTo(a)); // 降序
      String lastWeightID = weightIds.first;
      int lastNumber = int.parse(lastWeightID.substring(1));
      int newNumber = lastNumber + 1;
      return 'W${newNumber.toString().padLeft(5, '0')}';
    } catch (e) {
      print('Error generating weight ID: $e');
      return 'W00001';
    }
  }

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
      final weightId = await _generateWeightID();
      
      await _firestore.collection('WeightRecord').add({
        'WeightID': weightId,
        'UserID': userId,
        'Weight': weight,
        'RecordDate': today,
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
      print('=== WEIGHT SERVICE: recordWeightForDate ===');
      print('User ID: $userId');
      print('Weight: $weight');
      print('Date: $dateStr');
      
      final weightId = await _generateWeightID();
      
      await _firestore.collection('WeightRecord').add({
        'WeightID': weightId,
        'UserID': userId,
        'Weight': weight,
        'RecordDate': dateStr,
      });

      print('✅ Weight record added to database');

      // Only check goal achievement if recording for today
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      bool goalAchieved = false;
      
      print('Today: $today');
      print('Record date: $dateStr');
      print('Is today: ${dateStr == today}');
      
      if (dateStr == today) {
        print('Checking goal achievement for today...');
        goalAchieved = await _goalService.checkAndProcessGoalAchievement(userId, weight);
        print('Goal achieved result: $goalAchieved');
      } else {
        print('Not today, skipping goal achievement check');
      }
      
      final result = {
        'success': true,
        'goalAchieved': goalAchieved,
        'weight': weight,
      };
      
      print('Returning result: $result');
      return result;
    } catch (e) {
      print('❌ Error recording weight for date: $e');
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
          'weightId': data['WeightID'] ?? '',
          'weight': data['Weight'] ?? 0.0,
          'date': data['RecordDate'] ?? '',
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
          'weightId': data['WeightID'] ?? '',
          'weight': data['Weight'] ?? 0.0,
          'date': data['RecordDate'] ?? '',
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
          'weightId': data['WeightID'] ?? '',
          'weight': data['Weight'] ?? 0.0,
          'date': data['RecordDate'] ?? '',
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
