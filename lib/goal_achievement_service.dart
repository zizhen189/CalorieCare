import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';
import 'session_service.dart';
import 'calorie_adjustment_service.dart';

class GoalAchievementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CalorieAdjustmentService _adjustmentService = CalorieAdjustmentService();

  /// Check if user has achieved their goal based on current weight
  bool hasAchievedGoal(UserModel user, double currentWeight) {
    print('=== GOAL ACHIEVEMENT CHECK ===');
    print('User goal: "${user.goal}"');
    print('Current weight: $currentWeight');
    print('Target weight: ${user.targetWeight}');
    print('Goal type check: ${user.goal.runtimeType}');
    
    if (user.goal == 'maintain') {
      print('❌ User is in maintain mode, no goal to achieve');
      return false;
    }
    
    if (user.goal == 'loss' || user.goal == 'lose') {
      final achieved = currentWeight <= user.targetWeight;
      print('Loss goal: $currentWeight <= ${user.targetWeight} = $achieved');
      if (achieved) {
        print('🎉 LOSS GOAL ACHIEVED!');
      } else {
        print('❌ Loss goal not yet achieved');
      }
      return achieved;
    } else if (user.goal == 'gain') {
      final achieved = currentWeight >= user.targetWeight;
      print('Gain goal: $currentWeight >= ${user.targetWeight} = $achieved');
      if (achieved) {
        print('🎉 GAIN GOAL ACHIEVED!');
      } else {
        print('❌ Gain goal not yet achieved');
      }
      return achieved;
    }
    
    print('❌ Unknown goal type: "${user.goal}"');
    return false;
  }

  /// Process goal achievement and update all necessary data
  Future<Map<String, dynamic>> processGoalAchievement(String userId, double achievedWeight) async {
    try {
      print('=== PROCESSING GOAL ACHIEVEMENT ===');
      print('Processing goal achievement for user: $userId, weight: $achievedWeight');
      
      // Get current user data
      print('Step 1: Getting user data from Firestore...');
      final userQuery = await _firestore
          .collection('User')
          .where('UserID', isEqualTo: userId)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        print('❌ User not found in Firestore');
        return {'success': false, 'error': 'User not found'};
      }

      print('✅ User found in Firestore');
      final userDoc = userQuery.docs.first;
      final userData = userDoc.data();
      
      // Calculate new TDEE for maintenance
      print('Step 2: Calculating new TDEE...');
      final newTDEE = _calculateTDEE(userData, achievedWeight);
      print('New TDEE: $newTDEE');
      
      // Update Target collection only (not User collection)
      print('Step 3: Updating Target collection...');
      await _updateTargetCollection(userId, achievedWeight, newTDEE);
      print('✅ Target collection updated');
      
      // Handle active calorie adjustments
      print('Step 4: Handling active calorie adjustments...');
      await _handleActiveAdjustments(userId, newTDEE);
      print('✅ Active calorie adjustments handled');
      
      // Update session data
      print('Step 5: Updating session data...');
      await _updateSessionData(userId, achievedWeight, newTDEE);
      print('✅ Session data updated');
      
      print('🎉 Goal achievement processed successfully!');
      return {
        'success': true,
        'newTDEE': newTDEE,
        'achievedWeight': achievedWeight,
        'message': 'Congratulations! You have achieved your goal!'
      };
      
    } catch (e) {
      print('❌ Error processing goal achievement: $e');
      print('Error stack trace: ${StackTrace.current}');
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
      });
    }
  }

  /// Handle active calorie adjustments
  Future<void> _handleActiveAdjustments(String userId, double tdee) async {
    try {
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      print('Handling active adjustments for user: $userId, today: $todayStr');
      
      // Get all adjustments for the user
      final adjustmentsQuery = await _firestore
          .collection('CalorieAdjustment')
          .where('UserID', isEqualTo: userId)
          .get();

      print('Found ${adjustmentsQuery.docs.length} adjustments');

      for (var doc in adjustmentsQuery.docs) {
        final data = doc.data();
        final adjustDate = data['AdjustDate'] as String?;
        
        if (adjustDate == todayStr) {
          // Update today's adjustment to TDEE
          await doc.reference.update({
            'AdjustTargetCalories': tdee.round(),
            'UpdatedAt': FieldValue.serverTimestamp(),
          });
          print('Updated today\'s adjustment to TDEE: ${tdee.round()}');
        }
      }
      
      print('Goal achievement day: Using new TDEE instead of adjustments');
      
    } catch (e) {
      print('Error handling active adjustments: $e');
    }
  }

  /// Update session data
  Future<void> _updateSessionData(String userId, double achievedWeight, double tdee) async {
    try {
      final currentUser = await SessionService.getUserSession();
      if (currentUser != null && currentUser.userID == userId) {
        // Only update weight and TDEE, keep original goal and targetWeight
        final updatedUser = UserModel(
          userID: currentUser.userID,
          username: currentUser.username,
          email: currentUser.email,
          goal: currentUser.goal, // Keep original goal
          gender: currentUser.gender,
          height: currentUser.height,
          weight: achievedWeight, // Update current weight
          targetWeight: currentUser.targetWeight, // Keep original target weight
          activityLevel: currentUser.activityLevel,
          weeklyGoal: currentUser.weeklyGoal, // Keep original weekly goal
          bmi: currentUser.bmi,
          dailyCalorieTarget: tdee, // Update TDEE for maintenance
          tdee: tdee, // Update TDEE for maintenance
          currentStreakDays: currentUser.currentStreakDays,
          lastLoggedDate: currentUser.lastLoggedDate,
        );
        
        await SessionService.saveUserSession(updatedUser);
        print('Session data updated successfully (weight and TDEE only)');
      }
    } catch (e) {
      print('Error updating session data: $e');
    }
  }

  /// Check for goal achievement when weight is recorded
  Future<bool> checkAndProcessGoalAchievement(String userId, double newWeight) async {
    try {
      print('=== GOAL ACHIEVEMENT CHECK START ===');
      print('User ID: $userId');
      print('New Weight: $newWeight');
      
      final currentUser = await SessionService.getUserSession();
      if (currentUser == null || currentUser.userID != userId) {
        print('❌ User session not found for goal achievement check');
        print('Current user: ${currentUser?.userID}');
        print('Expected user: $userId');
        return false;
      }

      print('✅ User session found');
      print('Current user goal: "${currentUser.goal}"');
      print('Current user target weight: ${currentUser.targetWeight}');
      print('Current user weight: ${currentUser.weight}');

      // Only check if user has an active goal (not maintain)
      if (currentUser.goal == 'maintain') {
        print('❌ User is in maintain mode, skipping goal check');
        return false;
      }

      print('✅ User has active goal, checking achievement...');
      
      // Check if goal is achieved
      if (hasAchievedGoal(currentUser, newWeight)) {
        print('🎉 Goal achieved! Processing achievement...');
        final result = await processGoalAchievement(userId, newWeight);
        final success = result['success'] ?? false;
        print('Goal achievement processing result: $success');
        print('Result details: $result');
        return success;
      } else {
        print('❌ Goal not yet achieved');
        return false;
      }
    } catch (e) {
      print('❌ Error checking goal achievement: $e');
      return false;
    }
  }
}


