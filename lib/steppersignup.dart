import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/loading_utils.dart';
import 'package:caloriecare/session_service.dart';
import 'package:caloriecare/weight_service.dart';

class StepperSignUpPage extends StatefulWidget {
  const StepperSignUpPage({super.key});

  @override
  State<StepperSignUpPage> createState() => _StepperSignUpPageState();
}

class _StepperSignUpPageState extends State<StepperSignUpPage> {
  int _currentStep = 0;
  final PageController _pageController = PageController();

  // Form data
  String? goal;
  String? gender;
  DateTime? birthDate;
  int height = 170; // default height in cm
  double weight = 70.0; // default weight in kg
  double targetWeight = 65.0; // default target weight
  String? activityLevel;
  String username = '';
  String email = '';
  String password = '';
  String confirmPassword = '';

  // Calculated values
  double bmi = 0.0;
  double bmr = 0.0; // Add BMR
  double tdee = 0.0;
  double dailyCalorieTarget = 0.0; // Add daily calorie target

  // Add controllers
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _targetWeightController = TextEditingController();

  // Add password visibility control
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Add Firebase instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    // Initialize controllers with default values
    _heightController.text = height.toString();
    _weightController.text = weight.toString();
    _targetWeightController.text = targetWeight.toString();
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _targetWeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5AA162),
      resizeToAvoidBottomInset: false, // 防止键盘推动界面
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Account',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF5AA162),
              Color(0xFF7BB77E),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Stepper Content
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    // Step 1: Select Goal
                    _buildGoalSelection(),
                    // Step 2: Select Gender
                    _buildGenderSelection(),
                    // Step 3: Select Birth Date
                    _buildBirthDateSelection(),
                    // Step 4: Select Height
                    _buildHeightSelection(),
                    // Step 5: Select Weight
                    _buildWeightSelection(),
                    // Step 6: Show BMI
                    _buildBMICalculation(),
                    // Step 7: Select Target Weight (only if not maintain)
                    if (goal != 'maintain') _buildTargetWeightSelection(),
                    // Step 8: Select Activity Level
                    _buildActivityLevelSelection(),
                    // Step 9: Show Target Calories
                    _buildTDEECalculation(),
                    // Step 10: Registration Info
                    _buildRegistrationForm(),
                  ],
                ),
              ),
              // Navigation Buttons - 固定在底部
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // Back Button
                    if (_currentStep > 0)
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            // 收起键盘
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _currentStep--;
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            });
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            'BACK',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    
                    if (_currentStep > 0) const SizedBox(width: 20),
                    
                    // Next/Register Button
                    Expanded(
                      flex: _currentStep > 0 ? 1 : 1,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF5AA162),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () async {
                          // 收起键盘
                          FocusScope.of(context).unfocus();
                          
                          // Calculate the last step index based on goal
                          int lastStepIndex;
                          if (goal == 'maintain') {
                            lastStepIndex = 8; // Steps: 0-8 (9 total steps for maintain)
                          } else {
                            lastStepIndex = 9; // Steps: 0-9 (10 total steps for lose/gain)
                          }

                          if (_currentStep < lastStepIndex) {
                            if (_validateCurrentStep()) {
                              setState(() {
                                _currentStep++;
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );

                                if (_currentStep == 5) {
                                  _calculateBMI();
                                }

                                if (goal == 'maintain') {
                                  if (_currentStep == 7) {
                                    _calculateTDEE();
                                  }
                                } else {
                                  if (_currentStep == 8) {
                                    _calculateTDEE();
                                  }
                                }
                              });
                            }
                          } else {
                            // 最后一步 - 注册用户
                            if (_validateCurrentStep()) {
                              await _registerUser();
                            }
                          }
                        },
                        child: Text(
                          _currentStep == (goal == 'maintain' ? 8 : 9) ? 'SIGN UP' : 'NEXT',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        return goal != null;
      case 1:
        return gender != null;
      case 2:
        return birthDate != null;
      case 7:
        return activityLevel != null;
      case 8:
        if (goal == 'maintain') {
          return username.isNotEmpty && 
                 _isValidEmail(email) && 
                 _checkPasswordStrength(password) == 'strong' && 
                 password == confirmPassword;
        }
        return true;
      case 9:
        if (goal != 'maintain') {
          return username.isNotEmpty && 
                 _isValidEmail(email) && 
                 _checkPasswordStrength(password) == 'strong' && 
                 password == confirmPassword;
        }
        return true;
      default:
        return true;
    }
  }

  void _calculateBMI() {
    setState(() {
      bmi = weight / ((height / 100) * (height / 100));
    });
  }

  void _calculateTDEE() {
    // Add debug info
    print('Calculating TDEE with values:');
    print('Gender: $gender');
    print('Weight: $weight');
    print('Height: $height');
    print('BirthDate: $birthDate');
    print('Activity Level: $activityLevel');
    print('Goal: $goal');

    // Calculate age from birthDate
    int age = 0;
    if (birthDate != null) {
      age = DateTime.now().year - birthDate!.year;
      if (DateTime.now().month < birthDate!.month || 
          (DateTime.now().month == birthDate!.month && DateTime.now().day < birthDate!.day)) {
        age--;
      }
    }
    print('Calculated age: $age');

    // Calculate BMR using the new formula
    if (gender == 'male') {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }
    print('Calculated BMR: $bmr');

    // Apply activity level multiplier
    double activityMultiplier;
    switch (activityLevel) {
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
      default:
        activityMultiplier = 1.2;
    }
    print('Activity multiplier: $activityMultiplier');

    setState(() {
      tdee = bmr * activityMultiplier;
      print('Calculated TDEE: $tdee');
      _calculateDailyCalorieTarget();
      print('Final daily calorie target: $dailyCalorieTarget');
    });
  }

  void _calculateDailyCalorieTarget() {
    if (goal == 'maintain') {
      dailyCalorieTarget = tdee;
    } else {
      // Set weekly goal based on goal type
      double weeklyGoalValue;
      if (goal == 'lose') {
        weeklyGoalValue = 0.5; // 0.5 kg per week for weight loss
      } else if (goal == 'gain') {
        weeklyGoalValue = 0.25; // 0.25 kg per week for weight gain
      } else {
        weeklyGoalValue = 0.0; // maintain
      }
      
      double dailyAdjustment = (weeklyGoalValue * 7700) / 7;

      if (goal == 'lose') {
        dailyCalorieTarget = tdee - dailyAdjustment;
      } else if (goal == 'gain') {
        dailyCalorieTarget = tdee + dailyAdjustment;
      } else {
        dailyCalorieTarget = tdee;
      }
    }
  }

  // Add method to calculate target date
  String _calculateTargetDate() {
    if (goal == 'maintain') return '';
    
    double weeklyGoalValue;
    if (goal == 'lose') {
      weeklyGoalValue = 0.5;
    } else if (goal == 'gain') {
      weeklyGoalValue = 0.25;
    } else {
      return '';
    }
    
    double totalWeightToChange = (targetWeight - weight).abs();
    int weeksToGoal = (totalWeightToChange / weeklyGoalValue).ceil();
    
    DateTime targetDate = DateTime.now().add(Duration(days: weeksToGoal * 7));
    return '${targetDate.day}/${targetDate.month}/${targetDate.year}';
  }

  // Add method to calculate target date as Timestamp
  Timestamp? _calculateTargetDateTimestamp() {
    if (goal == 'maintain') return null;
    
    double weeklyGoalValue;
    if (goal == 'lose') {
      weeklyGoalValue = 0.5;
    } else if (goal == 'gain') {
      weeklyGoalValue = 0.25;
    } else {
      return null;
    }
    
    double totalWeightToChange = (targetWeight - weight).abs();
    int weeksToGoal = (totalWeightToChange / weeklyGoalValue).ceil();
    
    DateTime targetDate = DateTime.now().add(Duration(days: weeksToGoal * 7));
    return Timestamp.fromDate(targetDate);
  }

  Widget _buildGoalSelection() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 50,
            alignment: Alignment.center,
            child: const Text(
            'What is your goal?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 40),
          _buildGoalCard(
            title: 'Lose Weight',
            imagePath: 'assets/Loss.png',
            isSelected: goal == 'lose',
            onTap: () => setState(() => goal = 'lose'),
          ),
          const SizedBox(height: 20),
          _buildGoalCard(
            title: 'Gain Weight',
            imagePath: 'assets/Gain.png',
            isSelected: goal == 'gain',
            onTap: () => setState(() => goal = 'gain'),
          ),
          const SizedBox(height: 20),
          _buildGoalCard(
            title: 'Maintain Weight',
            imagePath: 'assets/Maintain.png',
            isSelected: goal == 'maintain',
            onTap: () => setState(() => goal = 'maintain'),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard({
    required String title,
    required String imagePath,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Card(
      color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Image.asset(
                imagePath,
                height: 60,
                width: 60,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    color: isSelected ? const Color(0xFF5AA162) : Colors.black, // 改为sage green
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderSelection() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 50,
            alignment: Alignment.center,
            child: const Text(
            'What is your gender?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: _buildGenderCard(
            title: 'Male',
                  imagePath: 'assets/Male.png',
            isSelected: gender == 'male',
            onTap: () => setState(() => gender = 'male'),
          ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildGenderCard(
            title: 'Female',
                  imagePath: 'assets/Female.png',
            isSelected: gender == 'female',
            onTap: () => setState(() => gender = 'female'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGenderCard({
    required String title,
    required String imagePath,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Card(
      color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                imagePath,
                height: 100,
                width: 100,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  color: isSelected ? const Color(0xFF5AA162) : Colors.black, // 改为sage green
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBirthDateSelection() {
    // Calculate the date 18 years ago
    final DateTime now = DateTime.now();
    final DateTime minDate = DateTime(now.year - 19, now.month, now.day);
    final DateTime maxDate = DateTime(now.year - 19, now.month, now.day);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 50,
            alignment: Alignment.center,
            child: const Text(
              'When is your birthday?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 40),
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: birthDate ?? minDate,
                  firstDate: DateTime(1900),
                  lastDate: maxDate,
                  builder: (BuildContext context, Widget? child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: Colors.blue,
                          onPrimary: Colors.white,
                          onSurface: Colors.black,
                        ),
                        textButtonTheme: TextButtonThemeData(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) {
                  setState(() {
                    birthDate = picked;
                  });
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      birthDate == null
                          ? 'Select your birthday'
                          : '${birthDate!.day}/${birthDate!.month}/${birthDate!.year}',
                      style: TextStyle(
                        fontSize: 18,
                        color: birthDate == null ? Colors.grey : Colors.black,
                      ),
                    ),
                    const Icon(Icons.calendar_today),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeightSelection() {
    final startHeight = 100;
    final endHeight = 250;
    final range = 20.0;
    final currentStart = (height - range / 2).clamp(startHeight, endHeight - range);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'What\'s your height?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            // Current height display
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text(
                    '$height',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'cm',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Text input field for height
            Container(
              width: 200,
              child: TextFormField(
                controller: _heightController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.2),
                  hintText: 'Enter height',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  suffixText: 'cm',
                  suffixStyle: const TextStyle(color: Colors.white, fontSize: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: Colors.white, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (value) {
                  final newHeight = int.tryParse(value);
                  if (newHeight != null && newHeight >= 100 && newHeight <= 250) {
                    setState(() {
                      height = newHeight;
                    });
                  }
                },
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Slider section
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Column(
                children: [
                  // Height range labels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${currentStart.round()}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        '${(currentStart + range).round()}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Enhanced slider track
                  GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        final RenderBox box = context.findRenderObject() as RenderBox;
                        final localPosition = box.globalToLocal(details.globalPosition);
                        final heightValue = ((localPosition.dx - 40) / (MediaQuery.of(context).size.width - 80)) * range + currentStart;
                        height = heightValue.clamp(startHeight, endHeight).round();
                        _heightController.text = height.toString();
                      });
                    },
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.2),
                            Colors.white.withOpacity(0.4),
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Scale marks
                          ...List.generate(range.toInt() + 1, (index) {
                            final position = (index / range) * (MediaQuery.of(context).size.width - 80);
                            final isMainMark = index % 5 == 0;
                            return Positioned(
                              top: 0,
                              bottom: 0,
                              left: position,
                              child: Center(
                                child: Container(
                                  width: isMainMark ? 2 : 1,
                                  height: isMainMark ? 16 : 10,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(isMainMark ? 0.8 : 0.5),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                            );
                          }),
                          
                          // Slider thumb
                          Positioned(
                            top: 5,
                            bottom: 5,
                            left: ((height - currentStart) / range) * (MediaQuery.of(context).size.width - 80) - 15,
                            child: Container(
                              width: 30,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.drag_indicator,
                                color: Color(0xFFC1FF72),
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildWeightSelection() {
    final minWeight = 35.0;
    final maxWeight = 150.0;
    final range = 20.0;
    final roundedWeight = (weight / 5).round() * 5.0;
    final currentStart = (roundedWeight - range / 2).clamp(minWeight, maxWeight - range);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'What\'s your weight?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            // Current weight display
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text(
                    weight.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'kg',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Text input field for weight
            Container(
              width: 200,
              child: TextFormField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.2),
                  hintText: 'Enter weight',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  suffixText: 'kg',
                  suffixStyle: const TextStyle(color: Colors.white, fontSize: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: Colors.white, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (value) {
                  final newWeight = double.tryParse(value);
                  if (newWeight != null && newWeight >= 35.0 && newWeight <= 150.0) {
                    setState(() {
                      weight = newWeight;
                    });
                  }
                },
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Slider section
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Column(
                children: [
                  // Weight range labels
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${currentStart.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        '${(currentStart + range).toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Enhanced slider track
                  GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        final RenderBox box = context.findRenderObject() as RenderBox;
                        final localPosition = box.globalToLocal(details.globalPosition);
                        final weightValue = ((localPosition.dx - 40) / (MediaQuery.of(context).size.width - 80)) * range + currentStart;
                        weight = (weightValue.clamp(minWeight, maxWeight) * 10).round() / 10;
                        _weightController.text = weight.toString();
                      });
                    },
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.2),
                            Colors.white.withOpacity(0.4),
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Scale marks
                          ...List.generate(range.toInt() + 1, (index) {
                            final position = (index / range) * (MediaQuery.of(context).size.width - 80);
                            final isMainMark = index % 5 == 0;
                            return Positioned(
                              top: 0,
                              bottom: 0,
                              left: position,
                              child: Center(
                                child: Container(
                                  width: isMainMark ? 2 : 1,
                                  height: isMainMark ? 16 : 10,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(isMainMark ? 0.8 : 0.5),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                            );
                          }),
                          
                          // Slider thumb
                          Positioned(
                            top: 5,
                            bottom: 5,
                            left: ((weight - currentStart) / range) * (MediaQuery.of(context).size.width - 80) - 15,
                            child: Container(
                              width: 30,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.drag_indicator,
                                color: Color(0xFFC1FF72),
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetWeightSelection() {
    final minWeight = 35.0;
    final maxWeight = 150.0;
    final range = 20.0;
    
    // Calculate healthy BMI range weights
    final heightInMeters = height / 100;
    final minHealthyWeight = 18.5 * heightInMeters * heightInMeters;
    final maxHealthyWeight = 24.9 * heightInMeters * heightInMeters;
    
    // Ensure valid bounds for healthy weight range
    final constrainedMinWeight = math.max(minWeight, minHealthyWeight).clamp(minWeight, maxWeight);
    final constrainedMaxWeight = math.min(maxWeight, maxHealthyWeight).clamp(minWeight, maxWeight);
    
    // Ensure min is always less than max
    final validMinWeight = math.min(constrainedMinWeight, constrainedMaxWeight - 1);
    final validMaxWeight = math.max(constrainedMaxWeight, constrainedMinWeight + 1);
    
    final roundedTargetWeight = (targetWeight / 2.5).round() * 2.5;
    
    // Calculate safe current start position
    final idealStart = roundedTargetWeight - range / 2;
    final maxStart = validMaxWeight - range;
    final currentStart = idealStart.clamp(validMinWeight, math.max(validMinWeight, maxStart));
    
    // Calculate target BMI
    final targetBMI = targetWeight / (heightInMeters * heightInMeters);
    final isHealthyBMI = targetBMI >= 18.5 && targetBMI <= 24.9;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            goal == 'lose' ? 'What\'s your target weight?' : 'What\'s your goal weight?',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 20),
          
          // Target weight display with BMI indicator
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  isHealthyBMI ? Colors.white.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              border: Border.all(
                color: isHealthyBMI ? Colors.white : Colors.red, 
                width: 2
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  targetWeight.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  'kg',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  'BMI: ${targetBMI.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isHealthyBMI ? Colors.white : Colors.red, // 健康BMI改为白色
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _getBMICategory(targetBMI),
                  style: TextStyle(
                    fontSize: 10,
                    color: isHealthyBMI ? Colors.white : Colors.red, // 健康BMI改为白色
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Text input field for target weight
          Container(
            width: 200,
            child: TextFormField(
              controller: _targetWeightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.2),
                hintText: 'Enter target weight',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                suffixText: 'kg',
                suffixStyle: const TextStyle(color: Colors.white, fontSize: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(
                    color: isHealthyBMI ? Colors.white : Colors.red,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                final newWeight = double.tryParse(value);
                if (newWeight != null && newWeight >= minWeight && newWeight <= maxWeight) {
                  setState(() {
                    targetWeight = newWeight;
                  });
                }
              },
            ),
          ),
          
          const SizedBox(height: 15),
          
          // BMI range information
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  'Healthy BMI Range: 18.5 - 24.9',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Recommended weight: ${validMinWeight.toStringAsFixed(1)} - ${validMaxWeight.toStringAsFixed(1)} kg',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Enhanced slider with numerical labels and BMI validation
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Column(
              children: [
                // Numerical labels
                SizedBox(
                  height: 25,
                  child: Stack(
                    children: List.generate(9, (index) {
                      final value = currentStart + (index * 2.5);
                      if (value < validMinWeight || value > validMaxWeight) {
                        return const SizedBox.shrink();
                      }
                      final position = (index * 2.5 / range) * (MediaQuery.of(context).size.width - 70);
                      return Positioned(
                        left: position - 15,
                        child: Container(
                          width: 30,
                          alignment: Alignment.center,
                          child: Text(
                            value.toStringAsFixed(0),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Slider track with BMI zones
                GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      final RenderBox box = context.findRenderObject() as RenderBox;
                      final localPosition = box.globalToLocal(details.globalPosition);
                      final weightValue = ((localPosition.dx - 35) / (MediaQuery.of(context).size.width - 70)) * range + currentStart;
                      
                      // Constrain to valid weight range
                      double newWeight = weightValue.clamp(validMinWeight, validMaxWeight);
                      
                      // Additional goal-specific constraints
                      if (goal == 'lose' && newWeight >= weight) {
                        newWeight = math.min(weight - 0.5, validMaxWeight);
                      } else if (goal == 'gain' && newWeight <= weight) {
                        newWeight = math.max(weight + 0.5, validMinWeight);
                      }
                      
                      targetWeight = (newWeight * 4).round() / 4; // Round to 0.25 kg
                      _targetWeightController.text = targetWeight.toString();
                    });
                  },
                  child: Container(
                    height: 35,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17.5),
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.withOpacity(0.3),
                          Colors.green.withOpacity(0.5),
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Scale marks for healthy range
                        ...List.generate(range.toInt() + 1, (index) {
                          final value = currentStart + index.toDouble();
                          if (value < validMinWeight || value > validMaxWeight) {
                            return const SizedBox.shrink();
                          }
                          final position = (index / range) * (MediaQuery.of(context).size.width - 70);
                          final isMainMark = value % 2.5 == 0;
                          return Positioned(
                            top: 0,
                            bottom: 0,
                            left: position,
                            child: Center(
                              child: Container(
                                width: isMainMark ? 2 : 1,
                                height: isMainMark ? 16 : 10,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(isMainMark ? 0.8 : 0.5),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                          );
                        }),
                      
                        // Slider thumb
                        Positioned(
                          top: 2,
                          bottom: 2,
                          left: ((targetWeight - currentStart) / range) * (MediaQuery.of(context).size.width - 70) - 15.5,
                          child: Container(
                            width: 31,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15.5),
                              border: Border.all(
                                color: isHealthyBMI ? Colors.green : Colors.red, 
                                width: 2
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              isHealthyBMI ? Icons.check : Icons.warning,
                              color: isHealthyBMI ? const Color(0xFF5AA162) : Colors.red, // 健康BMI用深绿色图标
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 15),
          
          // Warning message for unhealthy BMI
          if (!isHealthyBMI)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Target weight should result in a healthy BMI (18.5-24.9)',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBMICalculation() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          // Enhanced title
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: const Text(
              'Your Body Mass Index',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Enhanced BMI display with circular progress
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withOpacity(0.15),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                // BMI progress circle
                Positioned.fill(
                  child: CustomPaint(
                    painter: BMICirclePainter(bmi: bmi),
                  ),
                ),
                
                // BMI value and category
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        bmi.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'BMI',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: _getBMIColor(bmi).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _getBMIColor(bmi), width: 1),
                        ),
                        child: Text(
                          _getBMICategory(bmi),
                          style: TextStyle(
                            fontSize: 16,
                            color: _getBMIColor(bmi),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 40),
          
          // BMI information cards
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Height:',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '$height cm',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Weight:',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${weight.toStringAsFixed(1)} kg',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white30, height: 24),
                Text(
                  _getBMIDescription(bmi),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Color _getBMIColor(double bmi) {
    if (bmi < 18.5) return Colors.lightBlue;
    if (bmi < 25) return Colors.white; // 改为白色，在绿色背景上更清晰
    if (bmi < 30) return Colors.orange;
    return Colors.red;
  }

  String _getBMICategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    return 'Obese';
  }

  String _getBMIDescription(double bmi) {
    if (bmi < 18.5) return 'You may need to gain some weight. Consider consulting with a healthcare provider.';
    if (bmi < 25) return 'You have a healthy weight for your height. Keep up the good work!';
    if (bmi < 30) return 'You may benefit from losing some weight. A balanced diet and exercise can help.';
    return 'Consider consulting with a healthcare provider about weight management strategies.';
  }

  Widget _buildActivityLevelSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'What is your activity level?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 40),
          _buildSelectionCard(
            title: 'Sedentary (little or no exercise)',
            isSelected: activityLevel == 'sedentary',
            onTap: () => setState(() => activityLevel = 'sedentary'),
          ),
          const SizedBox(height: 20),
          _buildSelectionCard(
            title: 'Lightly active (light exercise 1-3 days/week)',
            isSelected: activityLevel == 'light',
            onTap: () => setState(() => activityLevel = 'light'),
          ),
          const SizedBox(height: 20),
          _buildSelectionCard(
            title: 'Moderately active (moderate exercise 3-5 days/week)',
            isSelected: activityLevel == 'moderate',
            onTap: () => setState(() => activityLevel = 'moderate'),
          ),
          const SizedBox(height: 20),
          _buildSelectionCard(
            title: 'Very active (hard exercise 6-7 days/week)',
            isSelected: activityLevel == 'very',
            onTap: () => setState(() => activityLevel = 'very'),
          ),
          const SizedBox(height: 20),
          _buildSelectionCard(
            title: 'Super active (very hard exercise & physical job)',
            isSelected: activityLevel == 'super',
            onTap: () => setState(() => activityLevel = 'super'),
          ),
        ],
      ),
    );
  }



  Widget _buildTDEECalculation() {
    // Recalculate every time it's displayed
    if (gender != null && weight > 0 && height > 0 && birthDate != null && activityLevel != null && goal != null) {
      _calculateTDEE();
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // BMR Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text(
                  'Your BMR',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  bmr.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  'calories per day',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Basal Metabolic Rate',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // TDEE Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text(
                  'Your TDEE',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  tdee.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  'calories per day',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Total Daily Energy Expenditure',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),
          
          // Daily Calorie Target Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5AA162), Color(0xFF84b882)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Your Daily Calorie Target',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  dailyCalorieTarget.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  'calories per day',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  goal == 'maintain' 
                    ? 'Based on your TDEE for weight maintenance'
                    : goal == 'lose'
                      ? 'Reduced from TDEE for weight loss'
                      : 'Increased from TDEE for weight gain',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          if (goal != 'maintain') ...[
            const SizedBox(height: 30),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Target Date',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _calculateTargetDate(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'You will reach your target weight on this date',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: 30),
          
          const Text(
            'Your TDEE is your daily calorie burn at rest and with activity. Your target is adjusted based on your weight goals.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationForm() {
    String passwordStrength = _checkPasswordStrength(password);
    bool passwordsMatch = password == confirmPassword && password.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Create Your Account',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 40),
          TextFormField(
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'Username',
              prefixIcon: const Icon(Icons.person),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => username = value,
          ),
          const SizedBox(height: 20),
          TextFormField(
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'Email',
              prefixIcon: const Icon(Icons.email),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              errorText: email.isNotEmpty && !_isValidEmail(email) ? 'Please enter a valid email' : null,
            ),
            onChanged: (value) {
              setState(() {
                email = value;
              });
            },
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 20),
          TextFormField(
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'Password',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() {
                password = value;
              });
            },
          ),
          if (password.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: passwordStrength == 'strong' ? 1.0 : 
                           passwordStrength == 'no_number' ? 0.75 :
                           passwordStrength == 'no_lowercase' ? 0.5 :
                           passwordStrength == 'no_uppercase' ? 0.25 : 0.0,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      passwordStrength == 'strong' ? Colors.green :
                      passwordStrength == 'no_number' ? Colors.lightGreen :
                      passwordStrength == 'no_lowercase' ? Colors.orange :
                      passwordStrength == 'no_uppercase' ? Colors.orangeAccent :
                      Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  passwordStrength == 'strong' ? 'Strong' :
                  passwordStrength == 'no_number' ? 'Good' :
                  passwordStrength == 'no_lowercase' ? 'Fair' :
                  passwordStrength == 'no_uppercase' ? 'Weak' :
                  'Too Short',
                  style: TextStyle(
                    color: passwordStrength == 'strong' ? Colors.green :
                           passwordStrength == 'no_number' ? Colors.lightGreen :
                           passwordStrength == 'no_lowercase' ? Colors.orange :
                           passwordStrength == 'no_uppercase' ? Colors.orangeAccent :
                           Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              passwordStrength == 'strong' ? 'Password is strong' :
              passwordStrength == 'no_number' ? 'Add a number' :
              passwordStrength == 'no_lowercase' ? 'Add a lowercase letter' :
              passwordStrength == 'no_uppercase' ? 'Add an uppercase letter' :
              'Password must be at least 8 characters',
              style: TextStyle(
                color: passwordStrength == 'strong' ? Colors.green :
                       passwordStrength == 'no_number' ? Colors.lightGreen :
                       passwordStrength == 'no_lowercase' ? Colors.orange :
                       passwordStrength == 'no_uppercase' ? Colors.orangeAccent :
                       Colors.red,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextFormField(
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'Confirm Password',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              errorText: confirmPassword.isNotEmpty && !passwordsMatch ? 'Passwords do not match' : null,
            ),
            onChanged: (value) {
              setState(() {
                confirmPassword = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionCard({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Card(
      color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                color: isSelected ? const Color(0xFF5AA162) : Colors.black, // 改为sage green
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Add password strength check method
  String _checkPasswordStrength(String password) {
    if (password.isEmpty) return 'empty';
    
    bool hasUppercase = password.contains(RegExp(r'[A-Z]'));
    bool hasLowercase = password.contains(RegExp(r'[a-z]'));
    bool hasNumber = password.contains(RegExp(r'[0-9]'));
    bool hasMinLength = password.length >= 8;

    if (!hasMinLength) return 'too_short';
    if (!hasUppercase) return 'no_uppercase';
    if (!hasLowercase) return 'no_lowercase';
    if (!hasNumber) return 'no_number';
    
    return 'strong';
  }

  // Add email validation method
  bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email);
  }

  // Add method to get next ID
  Future<String> _getNextUserId() async {
    final usersRef = _firestore.collection('User');
    final snapshot = await usersRef.orderBy('UserID', descending: true).limit(1).get();
    
    if (snapshot.docs.isEmpty) {
      return 'U00001';
    }
    
    String lastId = snapshot.docs.first.get('UserID');
    int number = int.parse(lastId.substring(1)) + 1;
    return 'U${number.toString().padLeft(5, '0')}';
  }

  Future<String> _getNextTargetId() async {
    final targetsRef = _firestore.collection('Target');
    final snapshot = await targetsRef.orderBy('TargetID', descending: true).limit(1).get();
    
    if (snapshot.docs.isEmpty) {
      return 'T00001';
    }
    
    String lastId = snapshot.docs.first.get('TargetID');
    int number = int.parse(lastId.substring(1)) + 1;
    return 'T${number.toString().padLeft(5, '0')}';
  }

  Future<String> _getNextStreakId() async {
    final streakRef = _firestore.collection('StreakRecord');
    final snapshot = await streakRef.orderBy('StreakID', descending: true).limit(1).get();
    if (snapshot.docs.isEmpty) {
      return 'S00001';
    }
    String lastId = snapshot.docs.first.get('StreakID');
    int number = int.parse(lastId.substring(1)) + 1;
    return 'S${number.toString().padLeft(5, '0')}';
  }

  // Modify registration method
  Future<void> _registerUser() async {
    try {
      // Show loading and perform registration
      final user = await LoadingUtils.showLoadingWhile(
        context,
        () async {
          // Create user authentication
          UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );

          // Get new user ID
          String userId = await _getNextUserId();

          // Save user data to User collection (using Firebase auto-generated document ID)
          DocumentReference userDocRef = await _firestore.collection('User').add({
            'UserID': userId,
            'UserName': username,
            'Email': email,
            'DOB': birthDate,
            'Gender': gender,
            'ActivityLevel': activityLevel,
            'Height': height,
            'Weight': weight,
            'BMR': bmr,
            'TDEE': tdee,
            'CreatedAt': FieldValue.serverTimestamp(),
          });

          // Create target record for all goals (including maintain)
          String targetId = await _getNextTargetId();
          // Calculate target duration (weeks) - for maintain, set to 0 or a default value
          double totalWeightChange = goal == 'maintain' ? 0 : (targetWeight - weight).abs();
          double weeklyChange;
          if (goal == 'lose') {
            weeklyChange = 0.5;
          } else if (goal == 'gain') {
            weeklyChange = 0.25;
          } else {
            weeklyChange = 0.0; // maintain
          }
          int targetDuration = goal == 'maintain' ? 0 : (totalWeightChange / weeklyChange).ceil();
          // Save target data to Target collection (using Firebase auto-generated document ID)
          await _firestore.collection('Target').add({
            'TargetID': targetId,
            'UserID': userId,
            'TargetType': goal, // 'lose', 'gain', or 'maintain'
            'TargetWeight': goal == 'maintain' ? weight : targetWeight,
            'WeeklyWeightChange': weeklyChange,
            'TargetDuration': targetDuration,
            'TargetCalories': dailyCalorieTarget,
            'EstimatedTargetDate': goal == 'maintain' ? null : _calculateTargetDateTimestamp(),
            'CreatedAt': FieldValue.serverTimestamp(),
          });

          // Create StreakRecord record
          String streakId = await _getNextStreakId();
          await _firestore.collection('StreakRecord').add({
            'StreakID': streakId,
            'UserID': userId,
            'CurrentStreakDays': 0,
            'LastLoggedDate': null,
          });

          // Record initial weight
          final weightService = WeightService();
          await weightService.recordWeight(userId, weight);

          // Create user model for navigation
          return UserModel(
            userID: userId,
            username: username,
            email: email,
            goal: goal!,
            gender: gender!,
            height: height,
            weight: weight,
            targetWeight: goal == 'maintain' ? weight : targetWeight,
            activityLevel: activityLevel!,
            weeklyGoal: goal == 'maintain' ? 'maintain' : (goal == 'lose' ? '0.5' : '0.25'),
            bmi: bmi,
            dailyCalorieTarget: dailyCalorieTarget,
            tdee: tdee,
            currentStreakDays: 0,
            lastLoggedDate: null,
          );
        },
        message: 'Creating account...',
      );

      // Save user session
      await SessionService.saveUserSession(user);

      // Navigate to home page
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/home',
          arguments: user,
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      if (e.code == 'weak-password') {
        errorMessage = 'Password is too weak.';
      } else if (e.code == 'email-already-in-use') {
        errorMessage = 'This email address is already registered';
      } else {
        errorMessage = 'Registration Failure: ${e.message}';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration Failures: $e')),
        );
      }
    }
  }
}

class BMICirclePainter extends CustomPainter {
  final double bmi;

  BMICirclePainter({required this.bmi});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;
    
    // Background circle
    final backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    
    canvas.drawCircle(center, radius, backgroundPaint);
    
    // Progress arc
    final progressPaint = Paint()
      ..color = _getBMIColorForPainter(bmi)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    
    // Calculate progress (BMI 15-35 mapped to 0-1)
    final progress = ((bmi - 15) / 20).clamp(0.0, 1.0);
    const startAngle = -3.14159 / 2; // Start from top
    final sweepAngle = 2 * 3.14159 * progress;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  Color _getBMIColorForPainter(double bmi) {
    if (bmi < 18.5) return Colors.blue;
    if (bmi < 25) return Colors.green;
    if (bmi < 30) return Colors.orange;
    return Colors.red;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}











