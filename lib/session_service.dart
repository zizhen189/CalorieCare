import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:caloriecare/user_model.dart';

class SessionService {
  static const String _userKey = 'user_data';
  static const String _isLoggedInKey = 'is_logged_in';

  // Save user data to SharedPreferences
  static Future<void> saveUserSession(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Convert UserModel to JSON string
    final userData = {
      'userID': user.userID,
      'username': user.username,
      'email': user.email,
      'goal': user.goal,
      'gender': user.gender,
      'height': user.height,
      'weight': user.weight,
      'targetWeight': user.targetWeight,
      'activityLevel': user.activityLevel,
      'weeklyGoal': user.weeklyGoal,
      'bmi': user.bmi,
      'dailyCalorieTarget': user.dailyCalorieTarget,
      'tdee': user.tdee,
      'currentStreakDays': user.currentStreakDays,
      'lastLoggedDate': user.lastLoggedDate?.toIso8601String(),
    };
    
    await prefs.setString(_userKey, jsonEncode(userData));
    await prefs.setBool(_isLoggedInKey, true);
  }

  // Get user data from SharedPreferences
  static Future<UserModel?> getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    
    final isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;
    if (!isLoggedIn) return null;
    
    final userDataString = prefs.getString(_userKey);
    if (userDataString == null) return null;
    
    try {
      final userData = jsonDecode(userDataString) as Map<String, dynamic>;
      
      return UserModel(
        userID: userData['userID'] ?? '',
        username: userData['username'] ?? '',
        email: userData['email'] ?? '',
        goal: userData['goal'] ?? '',
        gender: userData['gender'] ?? '',
        height: userData['height'] ?? 0,
        weight: userData['weight'] ?? 0.0,
        targetWeight: userData['targetWeight'] ?? 0.0,
        activityLevel: userData['activityLevel'] ?? '',
        weeklyGoal: userData['weeklyGoal'] ?? '',
        bmi: userData['bmi'] ?? 0.0,
        dailyCalorieTarget: userData['dailyCalorieTarget'] ?? 0.0,
        tdee: userData['tdee'] ?? 0.0,
        currentStreakDays: userData['currentStreakDays'] ?? 0,
        lastLoggedDate: userData['lastLoggedDate'] != null 
            ? DateTime.parse(userData['lastLoggedDate'])
            : null,
      );
    } catch (e) {
      print('Error parsing user session data: $e');
      return null;
    }
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  // Clear user session (logout)
  static Future<void> clearUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.setBool(_isLoggedInKey, false);
  }

  // Update user data in session
  static Future<void> updateUserSession(UserModel user) async {
    await saveUserSession(user);
  }
}