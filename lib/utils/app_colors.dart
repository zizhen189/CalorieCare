import 'package:flutter/material.dart';

class AppColors {
  // Primary sage green palette
  static const Color primary = Color(0xFF5AA162);
  static const Color primaryLight = Color(0xFF7BB77E);
  static const Color primaryDark = Color(0xFF4A8B4F);
  static const Color accent = Color(0xFF8FBC8F);
  
  // Background colors
  static const Color backgroundLight = Color(0xFFF0F7F0);
  static const Color backgroundDark = Color(0xFF1A1A1A);
  
  // Semantic colors
  static const Color success = Color(0xFF5AA162);
  static const Color warning = Color(0xFFE67E22);
  static const Color error = Color(0xFFE74C3C);
  static const Color info = Color(0xFF3498DB);
  
  // Meal colors (sage green variations)
  static const Color breakfast = Color(0xFF4A9B8E); // 青绿色 - 早餐
  static const Color lunch = Color(0xFF6BB6A7);     // 浅青绿 - 午餐  
  static const Color dinner = Color(0xFF2E7D6B);    // 深青绿 - 晚餐
  static const Color snack = Color(0xFF8FD4C1);     // 薄荷青 - 零食
  
  // Neutral colors
  static const Color textPrimary = Color(0xFF2C3E50);
  static const Color textSecondary = Color(0xFF7F8C8D);
  static const Color border = Color(0xFFE0E0E0);
  static const Color surface = Colors.white;
  
  // Gradient colors
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
  );
  
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, primaryLight],
  );
}
