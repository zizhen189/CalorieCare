import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'password_reset_service.dart';
import 'oob_password_reset_page.dart';

class OobCodeVerificationPage extends StatefulWidget {
  final String email;

  const OobCodeVerificationPage({super.key, required this.email});

  @override
  State<OobCodeVerificationPage> createState() => _OobCodeVerificationPageState();
}

class _OobCodeVerificationPageState extends State<OobCodeVerificationPage> {
  final TextEditingController _codeController = TextEditingController();
  final PasswordResetService _passwordResetService = PasswordResetService();
  bool _isLoading = false;
  String _errorMessage = '';
  bool _canResend = true;
  int _resendCountdown = 60;

  Future<void> _verifyCode() async {
    String input = _codeController.text.trim();
    
    if (input.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter the verification code or link';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      String oobCode = input;
      
      // 如果输入的是完整链接，提取OOB Code
      if (input.contains('oobCode=')) {
        final uri = Uri.parse(input);
        oobCode = uri.queryParameters['oobCode'] ?? '';
        
        if (oobCode.isEmpty) {
          setState(() {
            _errorMessage = 'Invalid link format';
            _isLoading = false;
          });
          return;
        }
      }
      
      final result = await _passwordResetService.verifyOobCode(oobCode);
      
      if (result['success']) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => OobPasswordResetPage(
                oobCode: oobCode,
                email: result['email'],
              ),
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = result['error'] ?? 'Invalid verification code or link';
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

  Future<void> _resendCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await _passwordResetService.sendFirebaseResetCode(widget.email);
      
      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New verification code sent to your email'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _errorMessage = result['error'] ?? 'Failed to resend code';
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
          'Verify Code',
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
                
                // Email Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.email_outlined,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Title
                const Text(
                  'Check Your Email',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 10),
                
                // Subtitle
                Text(
                  'We sent a password reset link to\n${widget.email}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                
                const SizedBox(height: 40),
                TextField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    labelText: 'Verification Code or Reset Link',
                    hintText: 'Paste code or entire link from email',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    suffixIcon: IconButton(
                      icon: Icon(Icons.paste),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          _codeController.text = data!.text!;
                        }
                      },
                    ),
                  ),
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _verifyCode(),
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
                // Verify Button
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
                    onPressed: _isLoading ? null : _verifyCode,
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: Color(0xFF5AA162), // Updated
                          )
                        : const Text(
                            'VERIFY CODE',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Resend Code
                TextButton(
                  onPressed: _canResend ? _resendCode : null,
                  child: Text(
                    _canResend 
                        ? 'Resend Code' 
                        : 'Resend in ${_resendCountdown}s',
                    style: TextStyle(
                      color: _canResend ? Colors.white : Colors.white.withOpacity(0.6),
                      fontSize: 16,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 20), // 添加底部间距
              ],
            ),
          ),
        ),
      ),
    );
  }
}





