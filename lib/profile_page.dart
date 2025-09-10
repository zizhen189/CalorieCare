import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/login.dart';
import 'package:caloriecare/homepage.dart';
import 'package:caloriecare/progress_page.dart';
import 'package:caloriecare/session_service.dart';
import 'package:caloriecare/calorie_adjustment_service.dart';
import 'package:caloriecare/auto_adjustment_service.dart';
import 'package:caloriecare/calorie_adjustment_page.dart';
import 'package:caloriecare/weight_service.dart';
import 'package:caloriecare/edit_profile_page.dart';
import 'package:caloriecare/refresh_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfilePage extends StatefulWidget {
  final UserModel? user;
  const ProfilePage({Key? key, this.user}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  UserModel? _currentUser; // Add this to track current user state
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  
  // Calorie adjustment related
  final CalorieAdjustmentService _adjustmentService = CalorieAdjustmentService();
  final AutoAdjustmentService _autoAdjustmentService = AutoAdjustmentService();
  final WeightService _weightService = WeightService();
  bool _autoAdjustEnabled = true;
  int _currentTargetCalories = 0;
  bool _isLoadingAdjustment = true;
  double? _latestWeight; // Store the latest weight from weight records

  // 添加密码强度检查方法（与注册页面相同）
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

  // 获取密码强度提示信息
  String _getPasswordStrengthMessage(String strength) {
    switch (strength) {
      case 'empty':
        return 'Please enter a password';
      case 'too_short':
        return 'Password must be at least 8 characters';
      case 'no_uppercase':
        return 'Password must contain at least one uppercase letter';
      case 'no_lowercase':
        return 'Password must contain at least one lowercase letter';
      case 'no_number':
        return 'Password must contain at least one number';
      case 'strong':
        return 'Password is strong';
      default:
        return 'Please enter a valid password';
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshUserData(); // 初始化时刷新数据
  }

  Future<void> _loadCalorieAdjustmentData() async {
    try {
      UserModel? currentUser = _displayUser ?? await SessionService.getUserSession();
      if (currentUser != null) {
        final currentTarget = await _adjustmentService.getCurrentActiveTargetCalories(currentUser.userID);
        final autoAdjustEnabled = await _adjustmentService.isAutoAdjustmentEnabled(currentUser.userID);
        
        setState(() {
          _currentTargetCalories = currentTarget;
          _autoAdjustEnabled = autoAdjustEnabled;
          _isLoadingAdjustment = false;
        });
      }
    } catch (e) {
      print('Error loading calorie adjustment data: $e');
      setState(() {
        _isLoadingAdjustment = false;
      });
    }
  }

  Future<void> _loadLatestWeight() async {
    try {
      UserModel? currentUser = _displayUser ?? await SessionService.getUserSession();
      if (currentUser != null) {
        // Get the latest weight record
        final weightHistory = await _weightService.getWeightHistory(currentUser.userID, limit: 1);
        if (weightHistory.isNotEmpty) {
          final latestRecord = weightHistory.first;
          final weight = latestRecord['weight'];
          double weightValue;
          if (weight is int) {
            weightValue = weight.toDouble();
          } else if (weight is double) {
            weightValue = weight;
          } else {
            weightValue = currentUser.weight ?? 0.0;
          }
          
          setState(() {
            _latestWeight = weightValue;
          });
        }
      }
    } catch (e) {
      print('Error loading latest weight: $e');
    }
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Re-authenticate user
        AuthCredential credential = EmailAuthProvider.credential(
          email: user.email!,
          password: _currentPasswordController.text,
        );
        
        await user.reauthenticateWithCredential(credential);
        
        // Update password
        await user.updatePassword(_newPasswordController.text);
        
        // Clear controllers
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        
        _showSuccessDialog('Success', 'Password updated successfully');
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'wrong-password':
          errorMessage = 'Current password is incorrect';
          break;
        case 'weak-password':
          errorMessage = 'New password is too weak';
          break;
        case 'requires-recent-login':
          errorMessage = 'Please logout and login again before changing password';
          break;
        default:
          errorMessage = 'Failed to update password: ${e.message}';
      }
      _showErrorDialog('Error', errorMessage);
    } catch (e) {
      _showErrorDialog('Error', 'An unexpected error occurred');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    try {
      // Clear session data
      await SessionService.clearUserSession();
      
      // Firebase logout
      await FirebaseAuth.instance.signOut();
      
      // Navigate to login page
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginPage()),
        (route) => false,
      );
    } catch (e) {
      _showErrorDialog('Error', 'Failed to logout');
    }
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 16,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 600,
                  maxWidth: 400,
                ),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        const Color(0xFFF8F9FA),
                      ],
                    ),
                  ),
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5AA162).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.lock_outline,
                                  color: Color(0xFF5AA162),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Change Password',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      'Update your account security',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Password must contain: at least 8 characters, one uppercase letter, one lowercase letter, and one number.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Current Password Field
                          _buildPasswordField(
                            controller: _currentPasswordController,
                            label: 'Current Password',
                            hint: 'Enter your current password',
                            obscureText: _obscureCurrentPassword,
                            onToggleVisibility: () {
                              setDialogState(() {
                                _obscureCurrentPassword = !_obscureCurrentPassword;
                              });
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your current password';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          
                          // New Password Field
                          _buildPasswordField(
                            controller: _newPasswordController,
                            label: 'New Password',
                            hint: 'Enter your new password',
                            obscureText: _obscureNewPassword,
                            onToggleVisibility: () {
                              setDialogState(() {
                                _obscureNewPassword = !_obscureNewPassword;
                              });
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a new password';
                              }
                              // 使用新的密码强度验证
                              final passwordStrength = _checkPasswordStrength(value);
                              if (passwordStrength != 'strong') {
                                return _getPasswordStrengthMessage(passwordStrength);
                              }
                              return null;
                            },
                          ),
                          // 密码强度提示
                          if (_newPasswordController.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _checkPasswordStrength(_newPasswordController.text) == 'strong' 
                                    ? Colors.green.shade50 
                                    : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _checkPasswordStrength(_newPasswordController.text) == 'strong' 
                                      ? Colors.green.shade200 
                                      : Colors.orange.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _checkPasswordStrength(_newPasswordController.text) == 'strong' 
                                        ? Icons.check_circle 
                                        : Icons.info,
                                    color: _checkPasswordStrength(_newPasswordController.text) == 'strong' 
                                        ? Colors.green 
                                        : Colors.orange,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _getPasswordStrengthMessage(_checkPasswordStrength(_newPasswordController.text)),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _checkPasswordStrength(_newPasswordController.text) == 'strong' 
                                            ? Colors.green.shade700 
                                            : Colors.orange.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          
                          // Confirm Password Field
                          _buildPasswordField(
                            controller: _confirmPasswordController,
                            label: 'Confirm New Password',
                            hint: 'Confirm your new password',
                            obscureText: _obscureConfirmPassword,
                            onToggleVisibility: () {
                              setDialogState(() {
                                _obscureConfirmPassword = !_obscureConfirmPassword;
                              });
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please confirm your new password';
                              }
                              if (value != _newPasswordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 32),
                          
                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: Colors.grey.shade300),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : () async {
                                    setDialogState(() {
                                      _isLoading = true;
                                    });
                                    await _changePassword();
                                    setDialogState(() {
                                      _isLoading = false;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF5AA162),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                  ),
                                  child: _isLoading 
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        'Update',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    required String? Function(String?) validator,
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
          obscureText: obscureText,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            suffixIcon: IconButton(
              onPressed: onToggleVisibility,
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey.shade600,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Close password dialog
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Logout'),
          content: Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _logout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  String _getAvatarAsset() {
    UserModel? currentUser = _displayUser;
    if (currentUser?.gender == null) return 'assets/Male.png';
    return currentUser!.gender.toLowerCase() == 'male'
        ? 'assets/Male.png'
        : 'assets/Female.png';
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshUserData() async {
    try {
      // Get fresh user data from session
      UserModel? freshUser = await SessionService.getUserSession();
      if (freshUser != null) {
        setState(() {
          _displayUser = freshUser;
        });
        
        // Also reload latest weight
        await _loadLatestWeight();
        
        print('Profile data refreshed successfully');
        print('Updated goal: ${freshUser.goal}');
        print('Updated target weight: ${freshUser.targetWeight}');
        print('Updated daily calories: ${freshUser.dailyCalorieTarget}');
      }
    } catch (e) {
      print('Error refreshing user data: $e');
    }
  }

  // Get the current user data to display
  UserModel? get _displayUser {
    return _currentUser ?? widget.user;
  }
  
  // Setter for _displayUser
  set _displayUser(UserModel? user) {
    _currentUser = user;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 当页面即将返回时刷新数据
        await _refreshUserData();
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false, // Remove back button
          title: const Text(
            'Profile',
            style: TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Info Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: AssetImage(_getAvatarAsset()),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _displayUser?.username ?? 'User',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _displayUser?.email ?? 'user@example.com',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // User Stats Section
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              'Height',
                              '${_displayUser?.height ?? 0} cm',
                              Icons.height,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildStatCard(
                              'Weight',
                              '${_latestWeight?.toStringAsFixed(1) ?? _displayUser?.weight?.toStringAsFixed(1) ?? 0} kg',
                              Icons.monitor_weight,
                              Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              'TDEE',
                              '${_displayUser?.tdee?.toStringAsFixed(0) ?? 0} cal',
                              Icons.local_fire_department,
                              Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              'Daily Target',
                              '${_displayUser?.dailyCalorieTarget?.toStringAsFixed(0) ?? 0} cal',
                              Icons.track_changes,
                              Colors.purple,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    
                      // Edit Profile Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                                                 onPressed: () async {
                           final result = await Navigator.push(
                             context,
                             MaterialPageRoute(
                               builder: (context) => EditProfilePage(user: _displayUser!),
                             ),
                           );
                          
                          if (result == true) {
                            // Reload fresh user data from database/session
                            await _refreshUserData();
                            // 触发全局刷新
                            RefreshManagerHelper.refreshAfterEditProfile();
                          }
                        },
                        icon: const Icon(Icons.edit, color: Colors.white),
                        label: const Text(
                          'Edit Profile',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5AA162),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Calorie Adjustment Section
              _buildCalorieAdjustmentSection(),
              const SizedBox(height: 24),
            
              // Settings Section
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
            
              // Change Password Option
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: Colors.blue,
                    ),
                  ),
                  title: const Text(
                    'Change Password',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Update your account password'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showChangePasswordDialog,
                ),
              ),
              const SizedBox(height: 12),

              // Blacklist Management Option
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.block,
                      color: Colors.red,
                    ),
                  ),
                  title: const Text(
                    'Manage Blacklist',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('View and manage blocked users'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showBlacklistManagement,
                ),
              ),
              const SizedBox(height: 12),

              // Privacy Policy Option
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.privacy_tip_outlined,
                      color: Colors.purple,
                    ),
                  ),
                  title: const Text(
                    'Privacy Policy',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('View our privacy policy'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showPrivacyPolicy,
                ),
              ),
              const SizedBox(height: 12),

              // Version Information
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.info_outline,
                      color: Colors.orange,
                    ),
                  ),
                  title: const Text(
                    'Version',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('CalorieCare v1.0.0'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Latest',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            
              // Delete Account Option
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.delete_forever,
                      color: Colors.red,
                    ),
                  ),
                  title: const Text(
                    'Delete Account',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text('Permanently delete your account and all data'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red),
                  onTap: _showDeleteAccountConfirmation,
                ),
              ),
              const SizedBox(height: 12),

              // Logout Option
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.logout,
                      color: Colors.red,
                    ),
                  ),
                  title: const Text(
                    'Logout',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text('Sign out of your account'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showLogoutConfirmation,
                ),
              ),
              const SizedBox(height: 80), // Add bottom padding for navigation bar
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 2, // Profile tab is selected
          onTap: (index) async {
            if (index == 0) {
              UserModel? currentUser = _displayUser ?? await SessionService.getUserSession();
              if (currentUser != null) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => HomePage(user: currentUser)),
                  (route) => false,
                );
              }
            } else if (index == 1) {
              UserModel? currentUser = _displayUser ?? await SessionService.getUserSession();
              if (currentUser != null) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => ProgressPage(user: currentUser)),
                  (route) => false,
                );
              }
            }
            // index == 2 is current page (Profile), so no navigation needed
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Progress'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildCalorieAdjustmentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Calorie Management',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        
        // Calorie Adjustment Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF5AA162).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.tune,
                color: Color(0xFF5AA162),
              ),
            ),
            title: const Text(
              'Calorie Adjustment',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Manage your daily calorie targets'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                         onTap: () async {
               UserModel? currentUser = _displayUser ?? await SessionService.getUserSession();
               if (currentUser != null) {
                 Navigator.push(
                   context,
                   MaterialPageRoute(
                     builder: (context) => CalorieAdjustmentPage(user: currentUser),
                   ),
                 ).then((_) => _loadCalorieAdjustmentData());
               }
             },
          ),
        ),
      ],
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.privacy_tip_outlined,
                        color: Colors.purple,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Privacy Policy',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            'Your privacy matters to us',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Privacy Policy Content
                Container(
                  height: 300,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPrivacySection(
                          'Data Collection',
                          'We collect information you provide directly to us, such as when you create an account, log your meals, or contact us for support.',
                        ),
                        _buildPrivacySection(
                          'How We Use Your Information',
                          'We use the information we collect to provide, maintain, and improve our services, including calculating your calorie needs and tracking your progress.',
                        ),
                        _buildPrivacySection(
                          'Information Sharing',
                          'We do not sell, trade, or otherwise transfer your personal information to third parties without your consent, except as described in this policy.',
                        ),
                        _buildPrivacySection(
                          'Data Security',
                          'We implement appropriate security measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction.',
                        ),
                        _buildPrivacySection(
                          'Contact Us',
                          'If you have any questions about this Privacy Policy, please contact us at privacy@caloriecare.com',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Close Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Close',
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
        );
      },
    );
  }

  Widget _buildPrivacySection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // Add this method for account deletion
  Future<void> _deleteAccount() async {
    setState(() {
      _isLoading = true;
    });

    try {
      UserModel? currentUser = _displayUser ?? await SessionService.getUserSession();
      if (currentUser == null) {
        throw Exception('User not found');
      }

      final userId = currentUser.userID;
      final db = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;

      // Delete from all collections
      await Future.wait([
        _deleteFromCollection(db, 'CalorieAdjustment', 'UserID', userId),
        _deleteFromCollection(db, 'LogMeal', 'UserID', userId),
        _deleteFromCollection(db, 'StreakRecord', 'UserID', userId),
        _deleteFromCollection(db, 'Target', 'UserID', userId),
        _deleteFromCollection(db, 'WeightRecord', 'UserID', userId),
        _deleteFromCollection(db, 'User', 'UserID', userId),
        _deleteLogMealListRecords(db, userId),
        _deleteSupervisionListRecords(db, userId),
        _deleteSupervisionRecords(db, userId),
        _deleteBlacklistRecords(db, userId),
      ]);

      // Clear session data
      await SessionService.clearUserSession();

      // Delete Firebase Auth account
      final user = auth.currentUser;
      if (user != null) {
        await user.delete();
      }

      // Navigate to login screen
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/',
          (route) => false,
        );
      }

      _showSuccessDialog('Account Deleted', 'Your account has been permanently deleted.');
    } catch (e) {
      print('Error deleting account: $e');
      _showErrorDialog('Deletion Failed', 'Failed to delete account: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteFromCollection(
    FirebaseFirestore db,
    String collection,
    String field,
    String userId,
  ) async {
    final query = await db.collection(collection).where(field, isEqualTo: userId).get();
    
    for (var doc in query.docs) {
      await doc.reference.delete();
    }
  }

  Future<void> _deleteLogMealListRecords(FirebaseFirestore db, String userId) async {
    // Get all LogMeal records for the user
    final logMealQuery = await db
        .collection('LogMeal')
        .where('UserID', isEqualTo: userId)
        .get();
    
    // Get all LogIDs from LogMeal records
    final logIds = logMealQuery.docs
        .map((doc) => doc['LogID'] as String)
        .toSet();

    // Delete LogMealList records for each LogID
    for (String logId in logIds) {
      final logMealListQuery = await db
          .collection('LogMealList')
          .where('LogID', isEqualTo: logId)
          .get();
      
      for (var doc in logMealListQuery.docs) {
        await doc.reference.delete();
      }
    }
  }

  Future<void> _deleteSupervisionListRecords(FirebaseFirestore db, String userId) async {
    // Get all supervision IDs where user is involved
    final supervisionListQuery = await db
        .collection('SupervisionList')
        .where('UserID', isEqualTo: userId)
        .get();
    
    final supervisionIds = supervisionListQuery.docs
        .map((doc) => doc['SupervisionID'] as String)
        .toSet();

    // Delete SupervisionList records for each SupervisionID
    for (String supervisionId in supervisionIds) {
      final supervisionListQuery = await db
          .collection('SupervisionList')
          .where('SupervisionID', isEqualTo: supervisionId)
          .get();
      
      for (var doc in supervisionListQuery.docs) {
        await doc.reference.delete();
      }
    }
  }

  Future<void> _deleteSupervisionRecords(FirebaseFirestore db, String userId) async {
    // Get all supervision IDs where user is involved
    final supervisionListQuery = await db
        .collection('SupervisionList')
        .where('UserID', isEqualTo: userId)
        .get();
    
    final supervisionIds = supervisionListQuery.docs
        .map((doc) => doc['SupervisionID'] as String)
        .toSet();

    // Delete supervision records
    for (String supervisionId in supervisionIds) {
      final supervisionQuery = await db
          .collection('Supervision')
          .where('SupervisionID', isEqualTo: supervisionId)
          .get();
      
      for (var doc in supervisionQuery.docs) {
        await doc.reference.delete();
      }
    }
  }

  Future<void> _deleteBlacklistRecords(FirebaseFirestore db, String userId) async {
    // Delete blacklist records where user is the one who blocked others (UserID)
    final userBlacklistQuery = await db
        .collection('Blacklist')
        .where('UserID', isEqualTo: userId)
        .get();
    
    for (var doc in userBlacklistQuery.docs) {
      await doc.reference.delete();
    }

    // Delete blacklist records where user is the one being blocked (BlockedUserID)
    final blockedBlacklistQuery = await db
        .collection('Blacklist')
        .where('BlockedUserID', isEqualTo: userId)
        .get();
    
    for (var doc in blockedBlacklistQuery.docs) {
      await doc.reference.delete();
    }
  }

  void _showDeleteAccountConfirmation() {
    String confirmText = '';
    bool isConfirmValid = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.warning,
                      color: Colors.red,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Delete Account',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This action cannot be undone. All your data will be permanently deleted including:',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '• Meal logs and calorie records\n'
                      '• Weight tracking data\n'
                      '• Streak records\n'
                      '• Supervision relationships\n'
                      '• Profile information\n'
                      '• Account settings',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Type "CONFIRM" to proceed:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: InputDecoration(
                        hintText: 'Type CONFIRM here',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isConfirmValid ? Colors.red : Colors.grey,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          confirmText = value;
                          isConfirmValid = value == 'CONFIRM';
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: isConfirmValid
                      ? () {
                          Navigator.of(context).pop();
                          _deleteAccount();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Delete Account',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Blacklist Management Methods
  void _showBlacklistManagement() async {
    try {
      UserModel? currentUser = _displayUser ?? await SessionService.getUserSession();
      if (currentUser == null) {
        _showErrorDialog('Error', 'User not found. Please login again.');
        return;
      }

      // 获取当前用户的黑名单
      List<Map<String, dynamic>> blockedUsers = await _getBlockedUsers(currentUser.userID);
      
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 16,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.92,
                  height: MediaQuery.of(context).size.height * 0.75,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        Colors.grey.shade50,
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
                  child: Column(
                    children: [
                      // Enhanced Header with gradient background
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.red.shade400,
                              Colors.red.shade600,
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.security,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Manage Blacklist',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'View and unblock users',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                splashRadius: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Content Area
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: blockedUsers.isEmpty
                              ? _buildEmptyBlacklistState()
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Stats Header
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.blue.shade200,
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            color: Colors.blue.shade600,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${blockedUsers.length} blocked user${blockedUsers.length == 1 ? '' : 's'}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.blue.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    // Users List
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount: blockedUsers.length,
                                        itemBuilder: (context, index) {
                                          final user = blockedUsers[index];
                                          return AnimatedContainer(
                                            duration: Duration(
                                              milliseconds: 300 + (index * 100),
                                            ),
                                            curve: Curves.easeOutBack,
                                            child: _buildBlockedUserCard(
                                              user,
                                              currentUser.userID,
                                              () async {
                                                // 重新获取黑名单并更新UI
                                                List<Map<String, dynamic>> updatedList = 
                                                    await _getBlockedUsers(currentUser.userID);
                                                setDialogState(() {
                                                  blockedUsers = updatedList;
                                                });
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      print('Error showing blacklist management: $e');
      _showErrorDialog('Error', 'Failed to load blacklist.');
    }
  }

  Widget _buildEmptyBlacklistState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Enhanced illustration with multiple layers
          Stack(
            alignment: Alignment.center,
            children: [
              // Background circle with gradient
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.green.shade100,
                      Colors.green.shade200,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
              // Inner circle
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: Colors.green.shade200,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.people_outline,
                  size: 40,
                  color: Colors.green.shade600,
                ),
              ),
              // Floating elements
              Positioned(
                top: 10,
                right: 15,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.shade300,
                  ),
                ),
              ),
              Positioned(
                bottom: 15,
                left: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.shade400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          // Enhanced title with better typography
          const Text(
            'No Blocked Users',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          
          // Enhanced description with better styling
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'You haven\'t blocked anyone yet.\nGreat for building connections!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.4,
                letterSpacing: 0.1,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          
          // Positive message card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.green.shade200,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.favorite,
                  color: Colors.green.shade600,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Stay positive!',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
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

  Widget _buildBlockedUserCard(Map<String, dynamic> user, String currentUserId, VoidCallback onUnblock) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.red.shade100,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.red.shade50,
                Colors.red.shade50,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Top row with avatar and user info
                Row(
                  children: [
                    // Enhanced Avatar with status indicator
                    Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.red.shade200,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.grey.shade100,
                            backgroundImage: AssetImage(
                              (user['Gender']?.toString().toLowerCase() == 'male') 
                                  ? 'assets/Male.png' 
                                  : 'assets/Female.png'
                            ),
                          ),
                        ),
                        // Blocked status indicator
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.block,
                              color: Colors.white,
                              size: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    
                    // Enhanced User Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Username with better typography
                          Text(
                            user['Username'] ?? user['BlockedUsername'] ?? 'Unknown User',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          
                          // Email with icon
                          Row(
                            children: [
                              Icon(
                                Icons.email_outlined,
                                size: 12,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  user['Email'] ?? user['BlockedEmail'] ?? 'No email',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    letterSpacing: 0.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Bottom row with status badge and button
                Row(
                  children: [
                    // Enhanced status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.red.shade600,
                            Colors.red.shade700,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.block,
                            size: 10,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 3),
                          const Text(
                            'Blocked',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // Compact Unblock Button
                    ElevatedButton(
                      onPressed: () => _showUnblockConfirmation(user, currentUserId, onUnblock),
                      child: const Text(
                        'Unblock',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5AA162),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 2,
                        minimumSize: const Size(60, 28),
                        shadowColor: const Color(0xFF5AA162).withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUnblockConfirmation(Map<String, dynamic> user, String currentUserId, VoidCallback onUnblock) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 16,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                   Colors.white,
                   Colors.green.shade50,
                 ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Enhanced Header
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.green.shade400,
                        Colors.green.shade600,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_add_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Title
                const Text(
                  'Unblock User',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                
                // User info card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: AssetImage(
                          (user['Gender']?.toString().toLowerCase() == 'male') 
                              ? 'assets/Male.png' 
                              : 'assets/Female.png'
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user['Username'] ?? 'Unknown User',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              user['Email'] ?? 'No email',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Description
                Text(
                  'Are you sure you want to unblock this user?',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                // Permissions info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.shade200,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.green.shade600,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'They will be able to:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Send you supervision invitations\n'
                        '• Find you in user searches\n'
                        '• Interact with you normally',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green.shade600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _unblockUser(currentUserId, user['UserID']);
                          onUnblock();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5AA162),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          'Unblock',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getBlockedUsers(String currentUserId) async {
    try {
      // 获取当前用户的黑名单记录
      QuerySnapshot blacklistQuery = await FirebaseFirestore.instance
          .collection('Blacklist')
          .where('UserID', isEqualTo: currentUserId)
          .get();
      
      List<Map<String, dynamic>> blockedUsers = [];
      
      for (var doc in blacklistQuery.docs) {
        var blacklistData = doc.data() as Map<String, dynamic>;
        
        // 直接使用Blacklist中存储的用户信息
        var userData = {
          'UserID': blacklistData['BlockedUserID'],
          'UserName': blacklistData['BlockedUsername'] ?? 'Unknown User',
          'Email': blacklistData['BlockedEmail'] ?? '',
          'BlacklistDocId': doc.id, // 保存黑名单文档ID以便删除
          'BlockID': blacklistData['BlockID'] ?? '',
        };
        
        blockedUsers.add(userData);
      }
      
      return blockedUsers;
    } catch (e) {
      print('Error getting blocked users: $e');
      return [];
    }
  }

  Future<void> _unblockUser(String currentUserId, String blockedUserId) async {
    try {
      // 删除黑名单记录
      QuerySnapshot blacklistQuery = await FirebaseFirestore.instance
          .collection('Blacklist')
          .where('UserID', isEqualTo: currentUserId)
          .where('BlockedUserID', isEqualTo: blockedUserId)
          .get();
      
      for (var doc in blacklistQuery.docs) {
        await doc.reference.delete();
      }
      
      // 显示成功消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('User unblocked successfully!'),
          backgroundColor: const Color(0xFF5AA162),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      print('Error unblocking user: $e');
      _showErrorDialog('Error', 'Failed to unblock user. Please try again.');
    }
  }
}






