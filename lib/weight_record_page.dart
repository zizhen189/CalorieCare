import 'package:flutter/material.dart';
import 'package:caloriecare/weight_service.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/session_service.dart';
import 'package:caloriecare/goal_achievement_page.dart'; // Added import for GoalAchievementPage

class WeightRecordPage extends StatefulWidget {
  final UserModel user;
  const WeightRecordPage({Key? key, required this.user}) : super(key: key);

  @override
  _WeightRecordPageState createState() => _WeightRecordPageState();
}

class _WeightRecordPageState extends State<WeightRecordPage> {
  final TextEditingController _weightController = TextEditingController();
  final WeightService _weightService = WeightService();
  bool _isLoading = false;

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _recordWeight() async {
    if (_weightController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a weight')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final weight = double.parse(_weightController.text);
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not found')),
        );
        return;
      }
      
      // Record weight and check for goal achievement
      final result = await _weightService.recordWeight(currentUser.userID, weight);
      
      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Weight recorded successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Check if goal was achieved
          if (result['goalAchieved'] == true) {
            // Navigate to goal achievement page
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => GoalAchievementPage(
                  achievedWeight: weight,
                  newTDEE: result['newTDEE'] ?? 2000.0,
                  user: currentUser,
                ),
              ),
            );
          } else {
            Navigator.of(context).pop(true); // 返回true表示记录成功
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Recording failed: ${result['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Weight'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            const SizedBox(height: 40),
            
            // 图标
            Icon(
              Icons.monitor_weight_outlined,
              size: 80,
              color: const Color(0xFF5AA162),
            ),
            
            const SizedBox(height: 30),
            
            // 标题
            const Text(
              'Today\'s Weight',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 10),
            
            const Text(
              'Please record your weight for today',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 40),
            
            // 体重输入框
            TextField(
              controller: _weightController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Weight (kg)',
                hintText: 'e.g. 65.5',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF5AA162), width: 2),
                ),
                prefixIcon: const Icon(Icons.monitor_weight, color: Color(0xFF5AA162)),
                suffixText: 'kg',
              ),
            ),
            
            const SizedBox(height: 40),
            
            // 记录按钮
            ElevatedButton(
              onPressed: _isLoading ? null : _recordWeight,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5AA162),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Record Weight',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
            ),
            
            const SizedBox(height: 20),
            
            // 跳过按钮
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Record Later',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
} 