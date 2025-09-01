import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/session_service.dart';
import 'package:caloriecare/calorie_adjustment_service.dart';
import 'package:caloriecare/refresh_manager.dart';

class EditProfilePage extends StatefulWidget {
  final UserModel user;
  
  const EditProfilePage({Key? key, required this.user}) : super(key: key);

  @override
  _EditProfilePageState createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _heightController = TextEditingController();
  final _targetWeightController = TextEditingController();
  
  String? _selectedGender;
  String? _selectedActivityLevel;
  String? _selectedGoal;
  DateTime? _selectedDOB;
  bool _isLoading = false;

  final Map<String, String> _activityLevels = {
    'sedentary': 'Sedentary',
    'light': 'Light Active',
    'moderate': 'Moderate Active',
    'very': 'Very Active',
    'super': 'Super Active',
  };

  final Map<String, String> _goals = {
    'loss': 'Weight Loss',
    'gain': 'Weight Gain',
    'maintain': 'Maintain Weight',
  };

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    _usernameController.text = widget.user.username;
    _heightController.text = widget.user.height.toString();
    _targetWeightController.text = widget.user.targetWeight.toString();
    
    // Handle gender value mapping
    String userGender = widget.user.gender;
    if (userGender == 'male' || userGender == 'female') {
      _selectedGender = userGender;
    } else {
      // Default to male if unknown value
      _selectedGender = 'male';
    }
    
    // Handle activity level value mapping
    String userActivityLevel = widget.user.activityLevel;
    if (_activityLevels.containsKey(userActivityLevel)) {
      _selectedActivityLevel = userActivityLevel;
    } else {
      // Default to sedentary if unknown value
      _selectedActivityLevel = 'sedentary';
    }
    
    // Handle goal value mapping
    String userGoal = widget.user.goal;
    if (userGoal == 'lose') {
      _selectedGoal = 'loss';
    } else if (userGoal == 'gain') {
      _selectedGoal = 'gain';
    } else if (userGoal == 'maintain') {
      _selectedGoal = 'maintain';
    } else {
      // Default to maintain if unknown value
      _selectedGoal = 'maintain';
    }
    
    // Get actual DOB from database
    _loadDOBFromDatabase();
  }

  Future<void> _loadDOBFromDatabase() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final userQuery = await firestore
          .collection('User')
          .where('UserID', isEqualTo: widget.user.userID)
          .get();
      
      if (userQuery.docs.isNotEmpty) {
        final userData = userQuery.docs.first.data();
        if (userData['DOB'] != null) {
          setState(() {
            _selectedDOB = (userData['DOB'] as Timestamp).toDate();
          });
        }
      }
    } catch (e) {
      print('Error loading DOB: $e');
      // Fallback to calculated DOB
      setState(() {
        _selectedDOB = DateTime.now().subtract(const Duration(days: 25 * 365));
      });
    }
  }

  DateTime? _calculateDOBFromAge() {
    // This is now just a fallback
    return DateTime.now().subtract(const Duration(days: 25 * 365));
  }

  double _calculateBMR(double weight, int height, int age, String gender) {
    if (gender.toLowerCase() == 'male') {
      return (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      return (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }
  }

  double _calculateTDEE(double bmr, String activityLevel) {
    double multiplier;
    switch (activityLevel) {
      case 'sedentary': multiplier = 1.2; break;
      case 'light': multiplier = 1.375; break;
      case 'moderate': multiplier = 1.55; break;
      case 'very': multiplier = 1.725; break;
      case 'super': multiplier = 1.9; break;
      default: multiplier = 1.2;
    }
    return bmr * multiplier;
  }

  double _calculateTargetCalories(double tdee, String goal, double currentWeight, double targetWeight) {
    if (goal == 'maintain') {
      return tdee;
    } else if (goal == 'loss') {
      return tdee - 500; // 500 calorie deficit for ~0.5kg/week loss
    } else { // gain
      return tdee + 300; // 300 calorie surplus for ~0.25kg/week gain
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final height = int.parse(_heightController.text);
      final targetWeight = double.parse(_targetWeightController.text);
      final age = DateTime.now().year - _selectedDOB!.year;
      
      // Calculate new values
      final bmr = _calculateBMR(widget.user.weight, height, age, _selectedGender!);
      final tdee = _calculateTDEE(bmr, _selectedActivityLevel!);
      final newTargetCalories = _calculateTargetCalories(tdee, _selectedGoal!, widget.user.weight, targetWeight);
      
      // Update Firebase
      await _updateFirebaseData(height, targetWeight, newTargetCalories, tdee);
      
      // Check and update auto-adjustment if needed
      await _handleAutoAdjustmentUpdate(newTargetCalories);
      
      // Update session with new user data
      await _updateUserSession(height, targetWeight, newTargetCalories, tdee);
      
      // Show success dialog
      _showSuccessDialog(newTargetCalories);
      
    } catch (e) {
      _showErrorDialog('Error updating profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateUserSession(int height, double targetWeight, double newTargetCalories, double tdee) async {
    // Create updated user model with new data
    final updatedUser = UserModel(
      userID: widget.user.userID,
      username: _usernameController.text,
      email: widget.user.email,
      goal: _selectedGoal!,
      gender: _selectedGender!,
      height: height,
      weight: widget.user.weight, // Keep current weight
      targetWeight: targetWeight,
      activityLevel: _selectedActivityLevel!,
      weeklyGoal: widget.user.weeklyGoal,
      bmi: widget.user.bmi,
      dailyCalorieTarget: newTargetCalories,
      tdee: tdee,
      currentStreakDays: widget.user.currentStreakDays,
      lastLoggedDate: widget.user.lastLoggedDate,
    );
    
    // Update session
    await SessionService.updateUserSession(updatedUser);
  }

  Future<void> _updateFirebaseData(int height, double targetWeight, double newTargetCalories, double tdee) async {
    final firestore = FirebaseFirestore.instance;
    
    // Find the user document by UserID field (not document ID)
    final userQuery = await firestore
        .collection('User')
        .where('UserID', isEqualTo: widget.user.userID)
        .get();
    
    if (userQuery.docs.isNotEmpty) {
      // Update User collection using the document reference
      await userQuery.docs.first.reference.update({
        'UserName': _usernameController.text,
        'Height': height,
        'Gender': _selectedGender,
        'DOB': Timestamp.fromDate(_selectedDOB!),
        'ActivityLevel': _selectedActivityLevel,
        'BMR': _calculateBMR(widget.user.weight, height, DateTime.now().year - _selectedDOB!.year, _selectedGender!),
        'TDEE': tdee,
      });
    }
    
    // Update Target collection (note: collection name is 'Target', not 'Targets')
    final targetsQuery = await firestore
        .collection('Target')
        .where('UserID', isEqualTo: widget.user.userID)
        .get();
    
    if (targetsQuery.docs.isNotEmpty) {
      // Calculate new weekly weight change and duration
      double weeklyChange;
      if (_selectedGoal == 'loss') {
        weeklyChange = 0.5;
      } else if (_selectedGoal == 'gain') {
        weeklyChange = 0.25;
      } else {
        weeklyChange = 0.0; // maintain
      }
      
      double totalWeightChange = _selectedGoal == 'maintain' ? 0 : (targetWeight - widget.user.weight).abs();
      int targetDuration = _selectedGoal == 'maintain' ? 0 : (totalWeightChange / weeklyChange).ceil();
      
      // Calculate new target date
      Timestamp? estimatedTargetDate;
      if (_selectedGoal != 'maintain' && totalWeightChange > 0) {
        int weeksToGoal = (totalWeightChange / weeklyChange).ceil();
        DateTime targetDate = DateTime.now().add(Duration(days: weeksToGoal * 7));
        estimatedTargetDate = Timestamp.fromDate(targetDate);
      }
      
      await targetsQuery.docs.first.reference.update({
        'TargetWeight': targetWeight,
        'TargetCalories': newTargetCalories,
        'TargetType': _selectedGoal,
        'WeeklyWeightChange': weeklyChange,
        'TargetDuration': targetDuration,
        'EstimatedTargetDate': estimatedTargetDate,
        'UpdatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _handleAutoAdjustmentUpdate(double newTargetCalories) async {
    final adjustmentService = CalorieAdjustmentService();
    
    // Check if there's an active adjustment for today
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    
    final adjustmentQuery = await FirebaseFirestore.instance
        .collection('CalorieAdjustment')
        .where('UserID', isEqualTo: widget.user.userID)
        .where('AdjustDate', isEqualTo: todayStr)
        .where('IsActive', isEqualTo: true)
        .get();
    
    if (adjustmentQuery.docs.isNotEmpty) {
      // Update today's adjustment to use new target
      await adjustmentQuery.docs.first.reference.update({
        'AdjustTargetCalories': newTargetCalories.round(),
        'UpdatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _showSuccessDialog(double newTargetCalories) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Success'),
          content: Text('Profile updated successfully!\nNew target calories: ${newTargetCalories.round()} kcal/day'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                // 触发全局刷新
                RefreshManagerHelper.refreshAfterEditProfile();
                Navigator.of(context).pop(true); // Return to profile with success flag
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildTextField(
                controller: _usernameController,
                label: 'Username',
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              _buildTextField(
                controller: _heightController,
                label: 'Height (cm)',
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your height';
                  }
                  final height = int.tryParse(value);
                  if (height == null || height < 100 || height > 250) {
                    return 'Please enter a valid height (100-250 cm)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              _buildDropdown(
                value: _selectedGender,
                label: 'Gender',
                items: {'male': 'Male', 'female': 'Female'},
                onChanged: (value) => setState(() => _selectedGender = value),
              ),
              const SizedBox(height: 20),
              
              _buildDatePicker(),
              const SizedBox(height: 20),
              
              _buildDropdown(
                value: _selectedActivityLevel,
                label: 'Activity Level',
                items: _activityLevels,
                onChanged: (value) => setState(() => _selectedActivityLevel = value),
              ),
              const SizedBox(height: 20),
              
              _buildTextField(
                controller: _targetWeightController,
                label: 'Target Weight (kg)',
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your target weight';
                  }
                  final targetWeight = double.tryParse(value);
                  if (targetWeight == null || targetWeight < 30 || targetWeight > 300) {
                    return 'Please enter a valid weight (30-300 kg)';
                  }
                  
                  // Goal-specific validation
                  if (_selectedGoal == 'loss' && targetWeight >= widget.user.weight) {
                    return 'Weight loss target must be less than current weight (${widget.user.weight}kg)';
                  } else if (_selectedGoal == 'gain' && targetWeight <= widget.user.weight) {
                    return 'Weight gain target must be greater than current weight (${widget.user.weight}kg)';
                  }
                  
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              _buildDropdown(
                value: _selectedGoal,
                label: 'Goal',
                items: _goals,
                onChanged: (value) {
                  setState(() => _selectedGoal = value);
                  // Trigger validation for target weight when goal changes
                  _formKey.currentState?.validate();
                },
              ),
              const SizedBox(height: 40),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5AA162), // Updated from #5AA162
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF5AA162), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String? value,
    required String label,
    required Map<String, String> items,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          onChanged: onChanged,
          validator: (value) => value == null ? 'Please select $label' : null,
          isExpanded: true, // This prevents overflow
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF5AA162), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          items: items.entries.map((entry) {
            return DropdownMenuItem<String>(
              value: entry.key,
              child: Text(
                entry.value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date of Birth',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _selectedDOB ?? DateTime.now().subtract(const Duration(days: 25 * 365)),
              firstDate: DateTime.now().subtract(const Duration(days: 100 * 365)),
              lastDate: DateTime.now().subtract(const Duration(days: 13 * 365)),
            );
            if (date != null) {
              setState(() => _selectedDOB = date);
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _selectedDOB != null
                  ? '${_selectedDOB!.day}/${_selectedDOB!.month}/${_selectedDOB!.year}'
                  : 'Select Date of Birth',
              style: TextStyle(
                color: _selectedDOB != null ? Colors.black87 : Colors.grey.shade600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}








