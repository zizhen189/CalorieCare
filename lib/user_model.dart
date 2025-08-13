// user_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String userID;
  final String username;
  final String email;
  final String goal; // loss, gain, maintain
  final String gender; // male, female
  final int height; // in cm
  final double weight; // in kg
  final double targetWeight; // in kg
  final String activityLevel; // sedentary, light, moderate, very, super
  final String weeklyGoal; // e.g., "0.5kg/week"
  final double bmi;
  final double dailyCalorieTarget;
  final double tdee; // Total Daily Energy Expenditure
  final int currentStreakDays;
  final DateTime? lastLoggedDate;

  UserModel({
    required this.userID,
    required this.username,
    required this.email,
    required this.goal,
    required this.gender,
    required this.height,
    required this.weight,
    required this.targetWeight,
    required this.activityLevel,
    required this.weeklyGoal,
    required this.bmi,
    required this.dailyCalorieTarget,
    required this.tdee,
    required this.currentStreakDays,
    required this.lastLoggedDate,
  });

  // Add firstName getter that extracts first name from username
  String get firstName {
    if (username.isEmpty) return 'User';
    final parts = username.split(' ');
    return parts.first;
  }

  // Convert to Map for saving to Firestore
  Map<String, dynamic> toMap() {
    return {
      'userID': userID,
      'username': username,
      'email': email,
      'goal': goal,
      'gender': gender,
      'height': height,
      'weight': weight,
      'targetWeight': targetWeight,
      'activityLevel': activityLevel,
      'weeklyGoal': weeklyGoal,
      'bmi': bmi,
      'dailyCalorieTarget': dailyCalorieTarget,
      'tdee': tdee,
      'currentStreakDays': currentStreakDays,
      'lastLoggedDate': lastLoggedDate?.toIso8601String(),
    };
  }

  // Create from Map (from Firestore)
  factory UserModel.fromMap(Map<String, dynamic> map) {
    // Helper to safely cast numbers
    double toDouble(dynamic val) {
      if (val is double) return val;
      if (val is int) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    // Helper to safely parse date
    DateTime? toDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return UserModel(
      userID: map['userID'] ?? map['UserID'] ?? '',
      username: map['username'] ?? map['UserName'] ?? '',
      email: map['email'] ?? map['Email'] ?? '',
      goal: map['goal'] ?? map['Goal'] ?? 'maintain',
      gender: map['gender'] ?? map['Gender'] ?? '',
      height: (map['height'] ?? map['Height'] ?? 0) as int,
      weight: toDouble(map['weight'] ?? map['Weight']),
      targetWeight: toDouble(map['targetWeight'] ?? map['TargetWeight']),
      activityLevel: map['activityLevel'] ?? map['ActivityLevel'] ?? '',
      weeklyGoal: map['weeklyGoal'] ?? map['WeeklyGoal'] ?? '',
      bmi: toDouble(map['bmi'] ?? map['BMI']),
      dailyCalorieTarget: toDouble(map['dailyCalorieTarget'] ?? map['TargetCalories']),
      tdee: toDouble(map['tdee'] ?? map['TDEE']),
      currentStreakDays: (map['currentStreakDays'] ?? map['CurrentStreakDays'] ?? 0) as int,
      lastLoggedDate: toDate(map['lastLoggedDate'] ?? map['LastLoggedDate']),
    );
  }

  // Create a copy with updated values
  UserModel copyWith({
    String? userID,
    String? username,
    String? email,
    String? goal,
    String? gender,
    int? height,
    double? weight,
    double? targetWeight,
    String? activityLevel,
    String? weeklyGoal,
    double? bmi,
    double? dailyCalorieTarget,
    double? tdee,
    int? currentStreakDays,
    DateTime? lastLoggedDate,
  }) {
    return UserModel(
      userID: userID ?? this.userID,
      username: username ?? this.username,
      email: email ?? this.email,
      goal: goal ?? this.goal,
      gender: gender ?? this.gender,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      targetWeight: targetWeight ?? this.targetWeight,
      activityLevel: activityLevel ?? this.activityLevel,
      weeklyGoal: weeklyGoal ?? this.weeklyGoal,
      bmi: bmi ?? this.bmi,
      dailyCalorieTarget: dailyCalorieTarget ?? this.dailyCalorieTarget,
      tdee: tdee ?? this.tdee,
      currentStreakDays: currentStreakDays ?? this.currentStreakDays,
      lastLoggedDate: lastLoggedDate ?? this.lastLoggedDate,
    );
  }
}
