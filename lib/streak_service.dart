import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class StreakService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Function to get today's date as a 'YYYY-MM-DD' string
  String _getTodayDate() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }
  
  // Function to get yesterday's date as a 'YYYY-MM-DD' string
  String _getYesterdayDate() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));
  }

  // Generate a new unique streak ID
  Future<String> _generateStreakID() async {
    QuerySnapshot snapshot = await _firestore
        .collection('StreakRecord')
        .orderBy('StreakID', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return 'S00001';
    }

    String lastStreakID = snapshot.docs.first['StreakID'];
    int lastNumber = int.parse(lastStreakID.substring(1));
    int newNumber = lastNumber + 1;
    return 'S${newNumber.toString().padLeft(5, '0')}';
  }

  /// Checks if the user's streak should be reset due to missing days
  /// Returns the updated streak count
  Future<int> checkAndResetStreakIfNeeded(String userId) async {
    final yesterdayStr = _getYesterdayDate();

    final streakQuery = await _firestore
        .collection('StreakRecord')
        .where('UserID', isEqualTo: userId)
        .limit(1)
        .get();

    if (streakQuery.docs.isEmpty) {
      return 0; // No streak record exists
    }

    final streakDoc = streakQuery.docs.first;
    final data = streakDoc.data();
    final lastLoggedDate = data['LastLoggedDate'];
    final currentStreak = data['CurrentStreakDays'] ?? 0;

    // If last logged date is not yesterday and not today, reset streak to 0
    if (lastLoggedDate != null && lastLoggedDate != yesterdayStr && lastLoggedDate != _getTodayDate()) {
      await streakDoc.reference.update({
        'CurrentStreakDays': 0,
        'LastLoggedDate': null,
      });
      return 0;
    }

    return currentStreak;
  }

  /// Updates the user's streak and returns the new streak data.
  ///
  /// Returns a map with `streakDays` and `isNewDay`.
  /// `isNewDay` is true if the streak was updated for the first time today.
  Future<Map<String, dynamic>> updateUserStreak(String userId) async {
    final todayStr = _getTodayDate();
    final yesterdayStr = _getYesterdayDate();

    final streakQuery = await _firestore
        .collection('StreakRecord')
        .where('UserID', isEqualTo: userId)
        .limit(1)
        .get();

    Map<String, dynamic> userStreakResult;

    if (streakQuery.docs.isEmpty) {
      // No streak record, create a new one.
      final newStreakId = await _generateStreakID();
      await _firestore.collection('StreakRecord').add({
        'StreakID': newStreakId,
        'UserID': userId,
        'CurrentStreakDays': 1,
        'LastLoggedDate': todayStr,
      });
      userStreakResult = {'streakDays': 1, 'isNewDay': true};
    } else {
      // Streak record exists, update it.
      final streakDoc = streakQuery.docs.first;
      final data = streakDoc.data();
      
      final lastLoggedDate = data['LastLoggedDate'];
      final currentStreak = data['CurrentStreakDays'] ?? 0;

      if (lastLoggedDate == todayStr) {
        // Already logged today, streak doesn't change.
        print('Streak already updated today, skipping update');
        userStreakResult = {'streakDays': currentStreak, 'isNewDay': false};
      } else if (lastLoggedDate == yesterdayStr) {
        // Logged yesterday, increment streak.
        final newStreak = currentStreak + 1;
        await streakDoc.reference.update({
          'CurrentStreakDays': newStreak,
          'LastLoggedDate': todayStr,
        });
        userStreakResult = {'streakDays': newStreak, 'isNewDay': true};
      } else {
        // Streak is broken, reset to 1.
        await streakDoc.reference.update({
          'CurrentStreakDays': 1,
          'LastLoggedDate': todayStr,
        });
        userStreakResult = {'streakDays': 1, 'isNewDay': true};
      }
    }

    // Check and update supervisor streak if user has supervision
    await _updateSupervisorStreakIfNeeded(userId);

    return userStreakResult;
  }

  /// Helper method to update supervisor streak if user has supervision
  Future<void> _updateSupervisorStreakIfNeeded(String userId) async {
    try {
      print('Checking supervisor streak for user: $userId');
      
      // Step 1: Check if user has supervision relationships
      final supervisionListQuery = await _firestore
          .collection('SupervisionList')
          .where('UserID', isEqualTo: userId)
          .get();

      if (supervisionListQuery.docs.isEmpty) {
        print('No supervision relationships found for user: $userId');
        return;
      }

      // Step 2: For each supervision relationship
      for (var supervisionListDoc in supervisionListQuery.docs) {
        final supervisionId = supervisionListDoc['SupervisionID'];
        print('Processing supervision: $supervisionId');
        
        // Step 3: Get supervision details
        final supervisionQuery = await _firestore
            .collection('Supervision')
            .where('SupervisionID', isEqualTo: supervisionId)
            .where('Status', isEqualTo: 'accepted')
            .limit(1)
            .get();

        if (supervisionQuery.docs.isEmpty) {
          print('No accepted supervision found for: $supervisionId');
          continue;
        }

        final supervisionData = supervisionQuery.docs.first.data();
        
        // Step 4: Get all users in this supervision
        final allUsersInSupervision = await _firestore
            .collection('SupervisionList')
            .where('SupervisionID', isEqualTo: supervisionId)
            .get();

        if (allUsersInSupervision.docs.length < 2) {
          print('Not enough users in supervision: $supervisionId');
          continue;
        }

        // Step 5: Get the other user (supervisor/supervisee)
        String? otherUserId;
        for (var doc in allUsersInSupervision.docs) {
          final docUserId = doc['UserID'];
          if (docUserId != userId) {
            otherUserId = docUserId;
            break;
          }
        }

        if (otherUserId == null) {
          print('Could not find other user in supervision: $supervisionId');
          continue;
        }

        print('Found other user: $otherUserId');

        // Step 6: Check if both users logged today
        final todayStr = _getTodayDate();
        
        // Check current user logged today
        final currentUserLogsToday = await _firestore
            .collection('LogMeal')
            .where('UserID', isEqualTo: userId)
            .where('LogDate', isEqualTo: todayStr)
            .get();

        // Check other user logged today
        final otherUserLogsToday = await _firestore
            .collection('LogMeal')
            .where('UserID', isEqualTo: otherUserId)
            .where('LogDate', isEqualTo: todayStr)
            .get();

        bool currentUserLoggedToday = currentUserLogsToday.docs.isNotEmpty;
        bool otherUserLoggedToday = otherUserLogsToday.docs.isNotEmpty;
        bool bothUsersLoggedToday = currentUserLoggedToday && otherUserLoggedToday;

        print('Current user logged today: $currentUserLoggedToday');
        print('Other user logged today: $otherUserLoggedToday');
        print('Both users logged today: $bothUsersLoggedToday');

        // Step 7: Update supervisor streak
        await updateSupervisorStreak(supervisionId, bothUsersLoggedToday);
      }
    } catch (e) {
      print('Error updating supervisor streak: $e');
    }
  }

  /// Checks if the supervisor streak should be reset due to missing days
  /// Returns the updated streak count for a specific supervision
  Future<int> checkAndResetSupervisorStreakIfNeeded(String supervisionId) async {
    final yesterdayStr = _getYesterdayDate();

    final supervisionQuery = await _firestore
        .collection('Supervision')
        .where('SupervisionID', isEqualTo: supervisionId)
        .limit(1)
        .get();

    if (supervisionQuery.docs.isEmpty) {
      return 0; // No supervision record exists
    }

    final supervisionDoc = supervisionQuery.docs.first;
    final data = supervisionDoc.data();
    final lastLoggedDate = data['LastLoggedDate'];
    final currentStreak = data['CurrentStreakDays'] ?? 0;

    // If last logged date is not yesterday and not today, reset streak to 0
    if (lastLoggedDate != null && lastLoggedDate != yesterdayStr && lastLoggedDate != _getTodayDate()) {
      await supervisionDoc.reference.update({
        'CurrentStreakDays': 0,
        'LastLoggedDate': null,
      });
      return 0;
    }

    return currentStreak;
  }

  /// Updates the supervisor's streak based on the same logic as user streak
  /// Returns a map with `streakDays` and `isNewDay`
  Future<Map<String, dynamic>> updateSupervisorStreak(String supervisionId, bool bothUsersLoggedToday) async {
    final todayStr = _getTodayDate();
    final yesterdayStr = _getYesterdayDate();

    print('Updating supervisor streak for supervision: $supervisionId, bothUsersLoggedToday: $bothUsersLoggedToday');

    final supervisionQuery = await _firestore
        .collection('Supervision')
        .where('SupervisionID', isEqualTo: supervisionId)
        .limit(1)
        .get();

    if (supervisionQuery.docs.isEmpty) {
      print('Supervision not found: $supervisionId');
      return {'streakDays': 0, 'isNewDay': false};
    }

    final supervisionDoc = supervisionQuery.docs.first;
    final data = supervisionDoc.data();
    final lastLoggedDate = data['LastLoggedDate'];
    final currentStreak = data['CurrentStreakDays'] ?? 0;

    print('Current supervision streak: $currentStreak, lastLoggedDate: $lastLoggedDate');

    // Only update if both users logged today
    if (!bothUsersLoggedToday) {
      print('Not both users logged today, keeping current streak: $currentStreak');
      return {'streakDays': currentStreak, 'isNewDay': false};
    }

    if (lastLoggedDate == todayStr) {
      // Already updated today, streak doesn't change
      print('Supervision streak already updated today');
      return {'streakDays': currentStreak, 'isNewDay': false};
    } else if (lastLoggedDate == yesterdayStr) {
      // Logged yesterday, increment streak
      final newStreak = currentStreak + 1;
      print('Incrementing supervision streak from $currentStreak to $newStreak');
      
      await supervisionDoc.reference.update({
        'CurrentStreakDays': newStreak,
        'LastLoggedDate': todayStr,
      });
      return {'streakDays': newStreak, 'isNewDay': true};
    } else {
      // Streak is broken, reset to 1
      print('Resetting supervision streak to 1 (was $currentStreak)');
      
      await supervisionDoc.reference.update({
        'CurrentStreakDays': 1,
        'LastLoggedDate': todayStr,
      });
      return {'streakDays': 1, 'isNewDay': true};
    }
  }
} 

