import 'package:flutter/material.dart';
import 'password_reset_service.dart';
import 'login.dart';

class PasswordResetPage extends StatefulWidget {
  final String verificationCode; // 重命名为verificationCode
  final String userId;
  final String email;

  const PasswordResetPage({
    super.key,
    required this.verificationCode, // 重命名为verificationCode
    required this.userId,
    required this.email,
  });

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  final PasswordResetService _passwordResetService = PasswordResetService();

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _isValidPassword(String password) {
    return password.length >= 6;
  }

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

  Future<void> _resetPassword() async {
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match';
      });
      return;
    }

    // 使用新的密码强度验证
    final passwordStrength = _checkPasswordStrength(_newPasswordController.text);
    if (passwordStrength != 'strong') {
      setState(() {
        _errorMessage = _getPasswordStrengthMessage(passwordStrength);
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 使用新的自定义密码重置方法
      final result = await _passwordResetService.resetPasswordCustom(
        widget.email,
        widget.verificationCode,
        _newPasswordController.text,
      );

      if (result['success']) {
        if (mounted) {
          // 直接跳转到登录页面，不显示弹窗
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => LoginPage()),
            (route) => false,
          );
        }
      } else {
        setState(() {
          _errorMessage = result['error'] ?? 'Failed to reset password';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5AA162), // Updated from #C1FF72
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Reset Password',
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
              Color(0xFF5AA162), // Updated primary
              Color(0xFF7BB77E), // Light sage green
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 40),
                
                // Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Title
                const Text(
                  'Create New Password',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 10),
                
                // Subtitle
                Text(
                  'Enter a new password for ${widget.email}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                
                const SizedBox(height: 40),
                // 新密码输入框
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNewPassword,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'New Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureNewPassword = !_obscureNewPassword;
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
                      _errorMessage = '';
                    });
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
                // 确认密码输入框
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
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
                  ),
                  onChanged: (value) {
                    setState(() {
                      _errorMessage = '';
                    });
                  },
                ),
                if (_errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 15),
                  Text(
                    _errorMessage,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                // Reset Password Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF5AA162), // Updated
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: _isLoading ? null : _resetPassword,
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: Color(0xFF5AA162), // Updated
                          )
                        : const Text(
                            'RESET PASSWORD',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}





