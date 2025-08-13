import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';
import 'session_service.dart';
import 'calorie_adjustment_service.dart';

class GoalAchievementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CalorieAdjustmentService _adjustmentService = CalorieAdjustmentService();

  /// Check if user has achieved their goal based on current weight
  bool hasAchievedGoal(UserModel user, double currentWeight) {
    print('Checking goal achievement:');
    print('User goal: ${user.goal}');
    print('Current weight: $currentWeight');
    print('Target weight: ${user.targetWeight}');
    
    if (user.goal == 'maintain') {
      print('User is in maintain mode, no goal to achieve');
      return false;
    }
    
    if (user.goal == 'loss') {
      final achieved = currentWeight <= user.targetWeight;
      print('Loss goal: $currentWeight <= ${user.targetWeight} = $achieved');
      return achieved;
    } else if (user.goal == 'gain') {
      final achieved = currentWeight >= user.targetWeight;
      print('Gain goal: $currentWeight >= ${user.targetWeight} = $achieved');
      return achieved;
    }
    
    print('Unknown goal type: ${user.goal}');
    return false;
  }

  /// Process goal achievement and update all necessary data
  Future<Map<String, dynamic>> processGoalAchievement(String userId, double achievedWeight) async {
    try {
      print('Processing goal achievement for user: $userId, weight: $achievedWeight');
      
      // Get current user data
      final userQuery = await _firestore
          .collection('User')
          .where('UserID', isEqualTo: userId)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        return {'success': false, 'error': 'User not found'};
      }

      final userDoc = userQuery.docs.first;
      final userData = userDoc.data();
      
      // Calculate new TDEE for maintenance
      final newTDEE = _calculateTDEE(userData, achievedWeight);
      
      // Update User collection
      await userDoc.reference.update({
        'Goal': 'maintain',
        'Weight': achievedWeight,
        'TargetWeight': achievedWeight,
        'UpdatedAt': FieldValue.serverTimestamp(),
      });

      // Update Target collection
      await _updateTargetCollection(userId, achievedWeight, newTDEE);
      
      // Handle active calorie adjustments
      await _handleActiveAdjustments(userId, newTDEE);
      
      // Update session data
      await _updateSessionData(userId, achievedWeight, newTDEE);
      
      print('Goal achievement processed successfully');
      return {
        'success': true,
        'newTDEE': newTDEE,
        'achievedWeight': achievedWeight,
        'message': 'Congratulations! You have achieved your goal!'
      };
      
    } catch (e) {
      print('Error processing goal achievement: $e');
      return {'success': false, 'error': 'Failed to process goal achievement: $e'};
    }
  }

  /// Calculate TDEE for maintenance
  double _calculateTDEE(Map<String, dynamic> userData, double currentWeight) {
    final height = userData['Height'] ?? 170;
    final gender = userData['Gender'] ?? 'male';
    final activityLevel = userData['ActivityLevel'] ?? 'sedentary';
    
    // Calculate age from DOB
    int age = 25; // default
    final dobData = userData['DOB'];
    if (dobData != null) {
      try {
        DateTime dob;
        if (dobData is Timestamp) {
          dob = dobData.toDate();
        } else if (dobData is String) {
          dob = DateTime.parse(dobData);
        } else {
          print('Unknown DOB format: $dobData');
          dob = DateTime.now().subtract(const Duration(days: 25 * 365));
        }
        age = DateTime.now().year - dob.year;
        print('Calculated age: $age from DOB: $dob');
      } catch (e) {
        print('Error parsing DOB: $e');
        age = 25; // fallback to default
      }
    }
    
    // Calculate BMR using Mifflin-St Jeor equation
    double bmr;
    if (gender.toLowerCase() == 'male') {
      bmr = (10 * currentWeight) + (6.25 * height) - (5 * age) + 5;
    } else {
      bmr = (10 * currentWeight) + (6.25 * height) - (5 * age) - 161;
    }
    
    print('BMR calculation: weight=$currentWeight, height=$height, age=$age, gender=$gender');
    print('BMR result: $bmr');
    
    // Apply activity multiplier
    double activityMultiplier;
    switch (activityLevel.toLowerCase()) {
      case 'sedentary':
        activityMultiplier = 1.2;
        break;
      case 'light':
        activityMultiplier = 1.375;
        break;
      case 'moderate':
        activityMultiplier = 1.55;
        break;
      case 'very':
        activityMultiplier = 1.725;
        break;
      case 'super':
        activityMultiplier = 1.9;
        break;
      case 'lightly_active':
        activityMultiplier = 1.375;
        break;
      case 'moderately_active':
        activityMultiplier = 1.55;
        break;
      case 'very_active':
        activityMultiplier = 1.725;
        break;
      case 'extremely_active':
        activityMultiplier = 1.9;
        break;
      default:
        activityMultiplier = 1.2;
    }
    
    final tdee = bmr * activityMultiplier;
    print('TDEE calculation: BMR=$bmr, activity=$activityLevel, multiplier=$activityMultiplier');
    print('TDEE result: $tdee');
    
    return tdee;
  }

  /// Update Target collection with maintenance data
  Future<void> _updateTargetCollection(String userId, double achievedWeight, double tdee) async {
    final targetQuery = await _firestore
        .collection('Target')
        .where('UserID', isEqualTo: userId)
        .limit(1)
        .get();

    if (targetQuery.docs.isNotEmpty) {
      await targetQuery.docs.first.reference.update({
        'TargetType': 'maintain',
        'TargetWeight': achievedWeight,
        'WeeklyWeightChange': 0.0,
        'TargetDuration': 0,
        'TargetCalories': tdee.round(),
        'EstimatedTargetDate': null, // No target date for maintenance
        'UpdatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Create new target record if none exists
      await _firestore.collection('Target').add({
        'UserID': userId,
        'TargetType': 'maintain',
        'TargetWeight': achievedWeight,
        'WeeklyWeightChange': 0.0,
        'TargetDuration': 0,
        'TargetCalories': tdee.round(),
        'EstimatedTargetDate': null,
        'CreatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Handle active calorie adjustments
  Future<void> _handleActiveAdjustments(String userId, double tdee) async {
    try {
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      print('Handling active adjustments for user: $userId, today: $todayStr');
      
      // Get all active adjustments for the user
      final activeAdjustmentsQuery = await _firestore
          .collection('CalorieAdjustment')
          .where('UserID', isEqualTo: userId)
          .where('IsActive', isEqualTo: true)
          .get();

      print('Found ${activeAdjustmentsQuery.docs.length} active adjustments');

      for (var doc in activeAdjustmentsQuery.docs) {
        final data = doc.data();
        final adjustDate = data['AdjustDate'] as String?;
        
        if (adjustDate == todayStr) {
          // Update today's adjustment to TDEE
          await doc.reference.update({
            'AdjustTargetCalories': tdee.round(),
            'UpdatedAt': FieldValue.serverTimestamp(),
          });
          print('Updated today\'s active adjustment to TDEE: ${tdee.round()}');
        } else {
          // Deactivate other active adjustments
          await doc.reference.update({'IsActive': false});
          print('Deactivated adjustment for date: $adjustDate');
        }
      }
      
    } catch (e) {
      print('Error handling active adjustments: $e');
    }
  }

  /// Update session data
  Future<void> _updateSessionData(String userId, double achievedWeight, double tdee) async {
    try {
      final currentUser = await SessionService.getUserSession();
      if (currentUser != null && currentUser.userID == userId) {
        final updatedUser = UserModel(
          userID: currentUser.userID,
          username: currentUser.username,
          email: currentUser.email,
          goal: 'maintain',
          gender: currentUser.gender,
          height: currentUser.height,
          weight: achievedWeight,
          targetWeight: achievedWeight,
          activityLevel: currentUser.activityLevel,
          weeklyGoal: '0.0',
          bmi: currentUser.bmi,
          dailyCalorieTarget: tdee,
          tdee: tdee,
          currentStreakDays: currentUser.currentStreakDays,
          lastLoggedDate: currentUser.lastLoggedDate,
        );
        
        await SessionService.saveUserSession(updatedUser);
        print('Session data updated successfully');
      }
    } catch (e) {
      print('Error updating session data: $e');
    }
  }

  /// Check for goal achievement when weight is recorded
  Future<bool> checkAndProcessGoalAchievement(String userId, double newWeight) async {
    try {
      print('=== Goal Achievement Check ===');
      print('User ID: $userId');
      print('New Weight: $newWeight');
      
      final currentUser = await SessionService.getUserSession();
      if (currentUser == null || currentUser.userID != userId) {
        print('User session not found for goal achievement check');
        return false;
      }

      print('Current user goal: ${currentUser.goal}');
      print('Current user target weight: ${currentUser.targetWeight}');

      // Only check if user has an active goal (not maintain)
      if (currentUser.goal == 'maintain') {
        print('User is in maintain mode, skipping goal check');
        return false;
      }

      // Check if goal is achieved
      if (hasAchievedGoal(currentUser, newWeight)) {
        print('🎉 Goal achieved! Processing achievement...');
        final result = await processGoalAchievement(userId, newWeight);
        final success = result['success'] ?? false;
        print('Goal achievement processing result: $success');
        return success;
      } else {
        print('Goal not yet achieved');
        return false;
      }
    } catch (e) {
      print('Error checking goal achievement: $e');
      return false;
    }
  }
}


