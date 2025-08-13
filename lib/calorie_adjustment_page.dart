import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:caloriecare/calorie_adjustment_service.dart';
import 'package:caloriecare/auto_adjustment_service.dart';
import 'package:caloriecare/notification_service.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/session_service.dart';
import 'loading_utils.dart';

class CalorieAdjustmentPage extends StatefulWidget {
  final UserModel user;

  const CalorieAdjustmentPage({
    Key? key,
    required this.user,
  }) : super(key: key);

  @override
  State<CalorieAdjustmentPage> createState() => _CalorieAdjustmentPageState();
}

class _CalorieAdjustmentPageState extends State<CalorieAdjustmentPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CalorieAdjustmentService _adjustmentService = CalorieAdjustmentService();
  final AutoAdjustmentService _autoAdjustmentService = AutoAdjustmentService();
  final NotificationService _notificationService = NotificationService();
  
  List<Map<String, dynamic>> _adjustmentHistory = [];
  bool _isLoading = true;
  bool _autoAdjustEnabled = true;
  int _currentTargetCalories = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 加载调整历史
      final history = await _adjustmentService.getAdjustmentHistory(currentUser.userID);
      
      // 获取当前目标卡路里
      final currentTarget = await _adjustmentService.getCurrentActiveTargetCalories(currentUser.userID);
      
      // 检查自动调整设置
      final autoAdjustEnabled = await _adjustmentService.isAutoAdjustmentEnabled(currentUser.userID);
      
      setState(() {
        _adjustmentHistory = history;
        _currentTargetCalories = currentTarget;
        _autoAdjustEnabled = autoAdjustEnabled;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading adjustment data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(
          message,
          overflow: TextOverflow.ellipsis,
        ),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Calorie Adjustment',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF5AA162),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF5AA162),
          tabs: const [
            Tab(text: 'Auto Adjustment'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAutoAdjustmentTab(),
                _buildHistoryTab(),
              ],
            ),
    );
  }

  Widget _buildAutoAdjustmentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current Target Display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text(
                  'Current Target Calories',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_currentTargetCalories cal',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5AA162),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Auto Adjustment Toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auto Adjustment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Automatically adjust your calorie target daily at midnight based on your intake patterns',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _autoAdjustEnabled,
                  onChanged: (value) async {
                    setState(() {
                      _autoAdjustEnabled = value;
                    });
                    
                    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
                    if (currentUser != null) {
                      // 保存设置
                      await _adjustmentService.setAutoAdjustmentEnabled(currentUser.userID, value);
                      
                      // 启动或停止自动调整服务
                      if (value) {
                        await _autoAdjustmentService.startAutoAdjustment(currentUser.userID);
                      } else {
                        _autoAdjustmentService.stopAutoAdjustment();
                      }
                    }
                  },
                  activeColor: const Color(0xFF5AA162),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // How It Works Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF5AA162)),
                    SizedBox(width: 8),
                    Text(
                      'How Auto Adjustment Works',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  'The system automatically adjusts your calorie target every day at midnight based on your previous day\'s intake:',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '• If you exceed your target, tomorrow\'s target will be reduced\n'
                  '• If you eat below your target, tomorrow\'s target will be increased\n'
                  '• Adjustments respect your goal type (gain/loss/maintain)\n'
                  '• All changes stay within safe health boundaries\n'
                  '• The system learns from your eating patterns over time',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Safety Boundaries Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.security, color: Color(0xFF5AA162)),
                    SizedBox(width: 8),
                    Text(
                      'Safety Boundaries',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'For your health and safety, adjustments are limited based on your goal:\n'
                  '• Weight Loss: Never below your BMR or gender minimum (1200♀/1500♂)\n'
                  '• Weight Gain: Never above TDEE + 500 calories\n'
                  '• Maintain: Both upper and lower limits apply\n'
                  '• All calculations use your personal age, gender, and activity level',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_adjustmentHistory.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No adjustment history yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Enable auto adjustment to start tracking changes',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _adjustmentHistory.length,
      itemBuilder: (context, index) {
        final adjustment = _adjustmentHistory[index];
        final adjustDate = adjustment['AdjustDate'] ?? '';
        final previousTarget = adjustment['PreviousTargetCalories'] ?? 0;
        final newTarget = adjustment['AdjustTargetCalories'] ?? 0;
        final adjustmentAmount = newTarget - previousTarget;
        final reason = adjustment['AdjustmentReason'] ?? '';
        final type = 'daily'; // 简化类型显示
        final isActive = false; // 不再使用IsActive字段

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    adjustDate,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5AA162),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      type.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '$previousTarget cal',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: Colors.grey,
                  ),
                  Text(
                    '$newTarget cal',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: adjustmentAmount > 0 ? Colors.orange : Colors.blue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${adjustmentAmount > 0 ? '+' : ''}$adjustmentAmount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                reason,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),

            ],
          ),
        );
      },
    );
  }
} 











