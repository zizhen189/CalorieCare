import 'package:caloriecare/streak_calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/log_food.dart';
import 'package:caloriecare/progress_page.dart';
import 'package:caloriecare/streak_service.dart'; // Added import for StreakService
import 'package:caloriecare/calorie_adjustment_service.dart'; // Added import for CalorieAdjustmentService
import 'package:caloriecare/auto_adjustment_service.dart'; // Added import for AutoAdjustmentService
import 'package:caloriecare/notification_service.dart'; // Added import for NotificationService
import 'package:caloriecare/invitation_notification_service.dart'; // Added import for InvitationNotificationService
import 'package:caloriecare/fcm_invitation_service.dart'; // Added import for FCM Invitation Service
import 'package:caloriecare/fcm_notification_service.dart'; // Added import for FCM Notification Service
import 'package:caloriecare/global_notification_manager.dart'; // Added import for Global Notification Manager
import 'package:caloriecare/meal_detail_page.dart'; // Added import for MealDetailPage
import 'package:caloriecare/weight_service.dart'; // Added import for WeightService
import 'package:caloriecare/weight_record_page.dart'; // Added import for WeightRecordPage
import 'package:caloriecare/profile_page.dart'; // Added import for ProfilePage
import 'package:shared_preferences/shared_preferences.dart'; // Added import for SharedPreferences
import 'package:caloriecare/session_service.dart'; // Added import for SessionService
import 'package:caloriecare/refresh_manager.dart'; // Added import for RefreshManager


void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  final UserModel? user;
  final DateTime? initialSelectedDate; // Add parameter to preserve selected date

  const HomePage({
    Key? key, 
    this.user,
    this.initialSelectedDate, // Add to constructor
  }) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  DateTime selectedDate = DateTime.now();
  int streakDays = 0;
  bool _hasLoggedToday = false;
  int kcalAvailable = 0;
  int kcalGoal = 0;
  DateTime? lastLoggedDate;
  int totalCaloriesConsumed = 0;
  Map<String, int> mealCalories = {
    'Breakfast': 0,
    'Lunch': 0,
    'Dinner': 0,
    'Snack': 0,
  };
  
  // Add adjustment-related variables
  bool _hasActiveAdjustment = false;
  int _originalTarget = 0;
  final AutoAdjustmentService _autoAdjustmentService = AutoAdjustmentService();
  // 使用全局通知管理器替代多个单独的服务
  final GlobalNotificationManager _globalNotificationManager = GlobalNotificationManager();
  // 保留原有服务作为备用
  final NotificationService _notificationService = NotificationService();
  final InvitationNotificationService _invitationService = InvitationNotificationService();
  
  // Add weight-related variables
  final WeightService _weightService = WeightService();
  bool _hasRecordedWeightToday = false;

  // Add refresh manager
  final RefreshManager _refreshManager = RefreshManager();
  late StreamSubscription<bool> _homePageRefreshSubscription;
  late StreamSubscription<bool> _calorieTargetRefreshSubscription;

  @override
  void initState() {
    super.initState();
    // Use initialSelectedDate if provided, otherwise default to today
    selectedDate = widget.initialSelectedDate ?? DateTime.now();
    _setupRefreshListeners();
    _checkSessionAndInitialize();
  }

  /// 设置刷新监听器
  void _setupRefreshListeners() {
    // 监听首页刷新事件
    _homePageRefreshSubscription = _refreshManager.homePageRefreshStream.listen((_) {
      print('📱 HomePage: Received refresh signal');
      _refreshAllData();
    });

    // 监听卡路里目标刷新事件
    _calorieTargetRefreshSubscription = _refreshManager.calorieTargetRefreshStream.listen((_) {
      print('🎯 HomePage: Received calorie target refresh signal');
      _refreshCalorieData();
    });
  }

  /// 刷新所有数据
  Future<void> _refreshAllData() async {
    print('🔄 HomePage: Refreshing all data...');
    await Future.wait([
      _loadTodayCalories(),
      _loadStreakData(),
      _loadAdjustedTarget(),
      _checkWeightRecord(),
    ]);
    print('✅ HomePage: All data refreshed');
  }

  /// 刷新卡路里相关数据
  Future<void> _refreshCalorieData() async {
    print('🔄 HomePage: Refreshing calorie data...');
    await Future.wait([
      _loadTodayCalories(),
      _loadAdjustedTarget(),
    ]);
    print('✅ HomePage: Calorie data refreshed');
  }

  @override
  void dispose() {
    _autoAdjustmentService.stopAutoAdjustment();
    // 停止全局通知管理器的用户监听器
    _globalNotificationManager.stopUserListeners();
    // 停止备用服务
    _notificationService.stopCustomMessageListener();
    _invitationService.stopInvitationListener();
    // 停止刷新监听器
    _homePageRefreshSubscription.cancel();
    _calorieTargetRefreshSubscription.cancel();
    super.dispose();
  }

  Future<void> _checkSessionAndInitialize() async {
    // Check if user is logged in via session
    final isLoggedIn = await SessionService.isLoggedIn();
    
    if (!isLoggedIn) {
      // No session found, navigate to login
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
      return;
    }

    // Get user from session
    UserModel? sessionUser = await SessionService.getUserSession();
    
    if (sessionUser == null) {
      // Session data is invalid, navigate to login
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
      return;
    }

    // Use session user if no user is passed to widget
    UserModel userToUse = widget.user ?? sessionUser;
    
    // Initialize with user data
    kcalGoal = userToUse.dailyCalorieTarget.round();
    _originalTarget = kcalGoal; // Store original target
    
    _loadTodayCalories();
    _loadStreakData();
    _loadAdjustedTarget(); // Load adjusted target if exists
    _startAutoAdjustment(); // Start auto adjustment service
    _checkWeightRecord(); // Check if weight has been recorded today
    _startGlobalNotificationManager(); // Start global notification manager (primary)
    // 注释掉旧服务以避免重复通知
    // _startCustomMessageListener(); // Start custom message listener  
    // _startInvitationListener(); // Start invitation listener
  }

  // New method to load streak data
  Future<void> _loadStreakData() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) return;
    final userId = currentUser.userID;

    // First check if streak needs to be reset
    final streakService = StreakService();
    await streakService.checkAndResetStreakIfNeeded(userId);

    final streakQuery = await FirebaseFirestore.instance
        .collection('StreakRecord')
        .where('UserID', isEqualTo: userId)
        .limit(1)
        .get();

    if (streakQuery.docs.isNotEmpty) {
      final data = streakQuery.docs.first.data();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      setState(() {
        streakDays = data['CurrentStreakDays'] ?? 0;
        _hasLoggedToday = data['LastLoggedDate'] == todayStr;
      });
    } else {
      setState(() {
        streakDays = 0;
        _hasLoggedToday = false;
      });
    }
  }

  // Check if weight has been recorded today
  Future<void> _checkWeightRecord() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) return;
    
    try {
      final hasRecorded = await _weightService.hasRecordedWeightToday(currentUser.userID);
      setState(() {
        _hasRecordedWeightToday = hasRecorded;
      });
      
      // Show weight reminder if not recorded today and not a new user
      if (!hasRecorded && mounted) {
        // Check if this is a new user (registered today)
        final isNewUser = await _isNewUser(currentUser.userID);
        
        // Check if user chose not to be reminded today
        final prefs = await SharedPreferences.getInstance();
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final skipReminderKey = 'skip_weight_reminder_${currentUser.userID}_$today';
        final skipReminderToday = prefs.getBool(skipReminderKey) ?? false;
        
        // Only show reminder if not a new user and user hasn't chosen to skip today
        if (!isNewUser && !skipReminderToday) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showWeightReminder();
          });
        }
      }
    } catch (e) {
      print('Error checking weight record: $e');
    }
  }

  // Check if user is newly registered (today)
  Future<bool> _isNewUser(String userId) async {
    try {
      final userQuery = await FirebaseFirestore.instance
          .collection('User')
          .where('UserID', isEqualTo: userId)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        final userData = userQuery.docs.first.data();
        final createdAt = userData['CreatedAt'] as Timestamp?;
        
        if (createdAt != null) {
          final createdDate = createdAt.toDate();
          final today = DateTime.now();
          
          // Check if user was created today
          return createdDate.year == today.year &&
                 createdDate.month == today.month &&
                 createdDate.day == today.day;
        }
      }
      return false;
    } catch (e) {
      print('Error checking if user is new: $e');
      return false;
    }
  }

  // Show weight reminder dialog
  void _showWeightReminder() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.monitor_weight, color: const Color(0xFF5AA162)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Weight Record Reminder',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Text('You haven\'t recorded your weight today. We recommend recording your weight now.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Later', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _skipReminderToday();
              },
              child: Text('Don\'t remind today', style: TextStyle(color: Colors.orange)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
                if (currentUser != null) {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WeightRecordPage(user: currentUser),
                    ),
                  );
                  
                  // Refresh weight record status
                  if (result == true) {
                    _checkWeightRecord();
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5AA162),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Record Weight'),
            ),
          ],
        );
      },
    );
  }

  // Skip weight reminder for today
  Future<void> _skipReminderToday() async {
    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) return;
      
      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final skipReminderKey = 'skip_weight_reminder_${currentUser.userID}_$today';
      
      await prefs.setBool(skipReminderKey, true);
      
      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Weight reminder disabled for today'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error skipping reminder: $e');
    }
  }

  // Start auto adjustment service - 添加重复启动检查
  Future<void> _startAutoAdjustment() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) return;
    
    try {
      // 检查服务是否已经在运行
      if (_autoAdjustmentService.isRunning && 
          _autoAdjustmentService.currentUserId == currentUser.userID) {
        print('Auto adjustment service already running for current user');
        return;
      }
      
      // 检查是否启用自动调整
      final adjustmentService = CalorieAdjustmentService();
      final isEnabled = await adjustmentService.isAutoAdjustmentEnabled(currentUser.userID);
      
      if (isEnabled) {
        await _autoAdjustmentService.startAutoAdjustment(currentUser.userID);
        print('Auto adjustment service started for user ${currentUser.userID}');
      } else {
        print('Auto adjustment is disabled for user ${currentUser.userID}');
      }
    } catch (e) {
      print('Error starting auto adjustment service: $e');
    }
  }

  // Start global notification manager (primary notification system)
  Future<void> _startGlobalNotificationManager() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) {
      print('No current user found, cannot start global notification manager');
      return;
    }
    
    print('Starting Global Notification Manager for user: ${currentUser.userID}');
    
    try {
      await _globalNotificationManager.startUserListeners(
        currentUser.userID,
        onInvitationReceived: (supervisionId, supervisionData) {
          print('=== GLOBAL MANAGER INVITATION RECEIVED ===');
          print('Supervision ID: $supervisionId');
          print('Supervision Data: $supervisionData');
          
          // Show invitation dialog with delay to ensure UI is ready
          Future.delayed(Duration(milliseconds: 100), () {
            if (mounted) {
              _showInvitationDialog(supervisionId, supervisionData);
            }
          });
        },
        onMessageReceived: (message) {
          print('=== GLOBAL MANAGER MESSAGE RECEIVED ===');
          print('Message: ${message.notification?.title}');
          // 可以在这里处理其他类型的消息
        },
      );
      
      print('Global Notification Manager started successfully');
      
      // 输出状态信息用于调试
      final status = _globalNotificationManager.getStatus();
      print('Global Notification Manager Status: $status');
      
      // 全局通知管理器启动完成
    } catch (e) {
      print('Error starting Global Notification Manager: $e');
    }
  }

  // Start custom message listener
  Future<void> _startCustomMessageListener() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) {
      print('No current user found, cannot start custom message listener');
      return;
    }
    
    print('Starting custom message listener for user: ${currentUser.userID}');
    
    try {
      // Initialize notification service
      await _notificationService.initialize();
      print('Notification service initialized successfully');
      
      // Start listening for custom messages
      await _notificationService.startCustomMessageListener(currentUser.userID);
      
      print('Custom message listener started successfully for user: ${currentUser.userID}');
    } catch (e) {
      print('Error starting custom message listener: $e');
    }
  }

  // Start invitation listener
  Future<void> _startInvitationListener() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) {
      print('No current user found, cannot start invitation listener');
      return;
    }
    
    print('Starting invitation listener for user: ${currentUser.userID}');
    
    try {
      // Initialize invitation service
      await _invitationService.initialize();
      print('Invitation service initialized successfully');
      
      // Start listening for invitations with callback
      await _invitationService.startInvitationListener(
        currentUser.userID,
        onInvitationReceived: (invitationId, supervisionData) {
          print('=== HOMEPAGE RECEIVED INVITATION ===');
          print('Invitation ID: $invitationId');
          print('Supervision Data: $supervisionData');
          print('Showing dialog to user...');
          print('Widget mounted: ${mounted}');
          
          // 使用Future.delayed确保在正确的时机显示对话框
          Future.delayed(Duration(milliseconds: 100), () {
            print('Future.delayed callback executed');
            if (mounted) {
              print('Showing dialog after delay...');
              _showInvitationDialog(invitationId, supervisionData);
            } else {
              print('Widget not mounted after delay');
            }
          });
        },
      );
      
      print('Invitation listener started successfully for user: ${currentUser.userID}');
    } catch (e) {
      print('Error starting invitation listener: $e');
    }
  }

  // Show invitation dialog
  void _showInvitationDialog(String supervisionDocId, Map<String, dynamic> supervisionData) {
    print('=== SHOWING INVITATION DIALOG ===');
    print('SupervisionDocId: $supervisionDocId');
    print('SupervisionData: $supervisionData');
    print('Context mounted: ${mounted}');
    
    if (!mounted) {
      print('Widget not mounted, cannot show dialog');
      return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        print('Dialog builder called');
        return AlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people, color: const Color(0xFF5AA162)),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Supervisor Invitation',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${supervisionData['InviterUserName'] ?? 'Someone'} invites you to become mutual supervisors.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF5AA162).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, size: 16, color: const Color(0xFF5AA162)),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'From: ${supervisionData['InviterUserName'] ?? 'Unknown'}',
                            style: TextStyle(fontSize: 14, color: const Color(0xFF5AA162)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.message, size: 16, color: const Color(0xFF5AA162)),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Message: Let\'s support each other in our health journey!',
                            style: TextStyle(fontSize: 14, color: const Color(0xFF5AA162)),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _handleInvitation(supervisionDocId, 'rejected'),
              child: Text('Decline', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () => _handleInvitation(supervisionDocId, 'accepted'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5AA162),
                foregroundColor: Colors.white,
              ),
              child: Text('Accept'),
            ),
          ],
        );
      },
    );
  }

  // Handle invitation response
  Future<void> _handleInvitation(String supervisionId, String status) async {
    print('=== HANDLING INVITATION ===');
    print('SupervisionId: $supervisionId');
    print('Status: $status');
    
    try {
      final db = FirebaseFirestore.instance;
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      
      if (currentUser == null) {
        throw Exception('User not found');
      }
      
      print('Current user: ${currentUser.userID}');
      
      // Find the supervision document by SupervisionID
      print('Searching for supervision with ID: $supervisionId');
      final supervisionQuery = await db
          .collection('Supervision')
          .where('SupervisionID', isEqualTo: supervisionId)
          .get();
      
      print('Supervision query results: ${supervisionQuery.docs.length} documents found');
      
      if (supervisionQuery.docs.isEmpty) {
        // 尝试查找所有Supervision记录来调试
        final allSupervisionQuery = await db
            .collection('Supervision')
            .limit(10)
            .get();
        
        print('All supervision records:');
        for (var doc in allSupervisionQuery.docs) {
          print('  - ${doc.id}: ${doc.data()}');
        }
        
        throw Exception('Supervision not found for ID: $supervisionId');
      }
      
      final supervisionDoc = supervisionQuery.docs.first;
      print('Found supervision document: ${supervisionDoc.id}');
      print('Supervision data: ${supervisionDoc.data()}');
      
      // Update supervision status
      await db.collection('Supervision').doc(supervisionDoc.id).update({
        'Status': status,
      });

      print('Supervision status updated to: $status');
      Navigator.of(context).pop(); // Close dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == 'accepted' ? 'Invitation accepted!' : 'Invitation declined.'),
          backgroundColor: status == 'accepted' ? const Color(0xFF5AA162) : Colors.orange,
        ),
      );
      
      // 如果接受了邀请，刷新supervision数据
      if (status == 'accepted') {
        print('Invitation accepted, refreshing supervision data...');
        
        // 确保Supervision记录有正确的初始数据
        await db.collection('Supervision').doc(supervisionDoc.id).update({
          'CurrentStreakDays': 0,
          'LastLoggedDate': null,
        });
        
        print('Supervision record initialized for streak tracking');
        
        // 触发相关数据刷新
        RefreshManagerHelper.refreshAfterAcceptSupervisor();
        
        // 可以在这里添加导航到streak calendar页面的逻辑
        // 或者显示一个提示，告诉用户可以在streak calendar中查看supervisor
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Supervisor relationship established! Check your streak calendar to see your supervisor.'),
            backgroundColor: const Color(0xFF5AA162),
            duration: Duration(seconds: 3),
          ),
        );
      }
      
    } catch (e) {
      print('Error handling invitation: $e');
      Navigator.of(context).pop(); // Close dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error handling invitation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Load today's calorie consumption
  Future<void> _loadTodayCalories() async {
    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null || currentUser.userID.isEmpty) return;
      String userID = currentUser.userID;

      // Get today's date
      String todayDate = '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

          // Query all LogMeal for today
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('LogMeal')
          .where('UserID', isEqualTo: userID)
          .where('LogDate', isEqualTo: todayDate)
          .get();

      // Reset meal calories
      Map<String, int> newMealCalories = {
        'Breakfast': 0,
        'Lunch': 0,
        'Dinner': 0,
        'Snack': 0,
      };

      int totalCalories = 0;
      for (DocumentSnapshot doc in snapshot.docs) {
        Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
        String mealType = data?['MealType'] ?? '';
        int calories = (data?['TotalCalories'] ?? 0) as int;
        
        if (newMealCalories.containsKey(mealType)) {
          newMealCalories[mealType] = calories;
        }
        totalCalories += calories;
      }

      setState(() {
        mealCalories = newMealCalories;
        totalCaloriesConsumed = totalCalories;
        kcalAvailable = kcalGoal - totalCalories;
      });
    } catch (e) {
      print('Error loading calories: $e');
    }
  }

  // Add method to load adjusted target
  Future<void> _loadAdjustedTarget() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) return;
    
    try {
      final adjustmentService = CalorieAdjustmentService();
      
      // 检查选择的日期是否是今天
      final today = DateTime.now();
      final isToday = selectedDate.year == today.year && 
                     selectedDate.month == today.month && 
                     selectedDate.day == today.day;
      
      int targetCalories;
      bool hasActiveAdjustment = false;
      
      if (isToday) {
        // 如果是今天，使用调整后的目标
        targetCalories = await adjustmentService.getCurrentActiveTargetCalories(currentUser.userID);
        
        // 检查是否有活跃的调整
        final adjustmentHistory = await adjustmentService.getAdjustmentHistory(currentUser.userID, limit: 1);
        hasActiveAdjustment = adjustmentHistory.isNotEmpty && targetCalories != _originalTarget;
        
        print('=== Loading Target for TODAY ===');
        print('Original target: $_originalTarget');
        print('Adjusted target: $targetCalories');
        print('Has active adjustment: $hasActiveAdjustment');
      } else {
        // 如果是历史日期，总是使用原始目标
        targetCalories = _originalTarget;
        hasActiveAdjustment = false;
        
        print('=== Loading Target for HISTORICAL DATE ===');
        print('Selected date: $selectedDate');
        print('Using original target: $targetCalories');
      }
      
      setState(() {
        kcalGoal = targetCalories;
        _hasActiveAdjustment = hasActiveAdjustment;
        kcalAvailable = kcalGoal - totalCaloriesConsumed;
      });
      
      print('Final kcalGoal: $kcalGoal');
      print('=== End Loading Target ===');
    } catch (e) {
      print('Error loading target: $e');
    }
  }

  // Get calories for a specific meal
  int _getMealCalories(String mealType) {
    return mealCalories[mealType] ?? 0;
  }

  Color getKcalColor() {
    double ratio = kcalGoal == 0 ? 0 : kcalAvailable / kcalGoal;
    if (ratio > 0.6) return Colors.green;
    if (ratio > 0.3) return Colors.orange;
    return Colors.red;
  }

  void _pickDate() async {
    DateTime? date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      setState(() {
        selectedDate = date;
      });
      // 重新加载选中日期的卡路里数据和目标
      _loadTodayCalories();
      _loadAdjustedTarget(); // 重新加载目标，因为历史日期应该显示原始目标
    }
  }

  void _logMeal(String mealType) async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LogFoodPage(
            mealType: mealType, 
            user: currentUser,
            selectedDate: selectedDate, // Pass the selected date
          ),
        ),
      ).then((_) {
        // When returning from LogFoodPage, reload calorie data for selected date
        _loadTodayCalories();
      });
    }
  }

  void _showMealDetail(String mealType) async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser != null) {
      // 显示餐点详情页面
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => MealDetailPage(
            mealType: mealType,
            user: currentUser,
            selectedDate: selectedDate,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              )),
              child: child,
            );
          },
          transitionDuration: Duration(milliseconds: 300),
        ),
      ).then((_) {
        // 返回时刷新数据
        _loadTodayCalories();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9), // Soft background
      body: CustomScrollView(
        slivers: [
          // Modern App Bar
          SliverAppBar(
            expandedHeight: 70, // 从120减少到80
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF5AA162),
            elevation: 0,
            automaticallyImplyLeading: false, // 禁用返回按钮
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF5AA162),
                      Color(0xFF7BB77E),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('EEEE').format(selectedDate),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12, // 从14减少到12
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _pickDate,
                                  child: Row(
                                    children: [
                                      Text(
                                        DateFormat('MMM dd, yyyy').format(selectedDate),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18, // 从20减少到18
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 6), // 从8减少到6
                                      const Icon(
                                        Icons.calendar_today,
                                        color: Colors.white70,
                                        size: 16, // 从18减少到16
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                // Debug button for auto adjustment
                                GestureDetector(
                                  onTap: _testAutoAdjustment,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.red.withOpacity(0.5)),
                                    ),
                                    child: const Text(
                                      'TEST',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Streak indicator with animation
                                GestureDetector(
                                  onTap: () async {
                                    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
                                    if (currentUser != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (context) => StreakCalendarPage(user: currentUser)),
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // 从16,8减少到12,6
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(18), // 从20减少到18
                                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        Image.asset(
                                          _hasLoggedToday ? 'assets/Logged.png' : 'assets/Notlog.png',
                                          width: 18, // 从20减少到18
                                          height: 18,
                                        ),
                                        const SizedBox(width: 4), // 从6减少到4
                                        Text(
                                          '$streakDays',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14, // 从16减少到14
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 3), // 从4减少到3

                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12), // 从16减少到12
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Main content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Enhanced Calorie Progress Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Progress Ring with enhanced styling
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Background circle
                            Container(
                              width: 220,
                              height: 220,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey.shade50,
                              ),
                            ),
                            // Progress indicator
                            SizedBox(
                              height: 200,
                              width: 200,
                              child: CircularProgressIndicator(
                                value: kcalGoal == 0 ? 0 : (kcalGoal - kcalAvailable) / kcalGoal,
                                strokeWidth: 12,
                                valueColor: AlwaysStoppedAnimation<Color>(getKcalColor()),
                                backgroundColor: Colors.grey.shade200,
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            // Center content
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  kcalAvailable < 0 ? '${(-kcalAvailable).abs()}' : '$kcalAvailable',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: getKcalColor(),
                                  ),
                                ),
                                Text(
                                  kcalAvailable < 0 ? 'Kcal over' : 'Kcal remaining',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF5AA162).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '$kcalGoal Kcal Goal',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF5AA162),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (_hasActiveAdjustment) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.tune,
                                          color: Color(0xFF5AA162),
                                          size: 12,
                                        ),
                                        const SizedBox(width: 2),
                                        const Text(
                                          'Adjusted',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF5AA162),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Quick stats row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildQuickStat('Consumed', '${kcalGoal - kcalAvailable}', 'kcal', Colors.orange),
                            Container(width: 1, height: 40, color: Colors.grey.shade300),
                            _buildQuickStat(
                              kcalAvailable < 0 ? 'Over' : 'Remaining', 
                              kcalAvailable < 0 ? '${(-kcalAvailable).abs()}' : '$kcalAvailable', 
                              'kcal', 
                              getKcalColor()
                            ),
                            Container(width: 1, height: 40, color: Colors.grey.shade300),
                            _buildQuickStat('Goal', '$kcalGoal', 'kcal', const Color(0xFF5AA162)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Meals section header
                  Row(
                    children: [
                      const Text(
                        'Today\'s Meals',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5AA162).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${totalCaloriesConsumed} kcal',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF5AA162),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Enhanced meal tiles
                  ...['Breakfast', 'Lunch', 'Dinner', 'Snack'].map((meal) => 
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildEnhancedMealTile(meal, _getMealCalories(meal)),
                    ),
                  ).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) async {
          if (index == 1) {
            UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
            if (currentUser != null) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProgressPage(user: currentUser)),
              );
            }
          } else if (index == 2) {
            UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
            if (currentUser != null) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProfilePage(user: currentUser)),
              );
            }
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Progress'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildQuickStat(String label, String value, String unit, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            fontSize: 10,
            color: color.withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedMealTile(String title, int kcal) {
    bool hasFood = kcal > 0;
    Color mealColor = getMealColor(title);
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: hasFood 
          ? Border.all(color: mealColor.withOpacity(0.2), width: 1)
          : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showMealDetail(title),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Meal icon with gradient background
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        mealColor.withOpacity(0.8),
                        mealColor,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getMealIcon(title),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // Meal info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (hasFood) 
                        Text(
                          '$kcal kcal',
                          style: TextStyle(
                            color: mealColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        )
                      else
                        Text(
                          'No food logged',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasFood) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: mealColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.visibility_outlined,
                              color: mealColor,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'View',
                              style: TextStyle(
                                color: mealColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: mealColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.add,
                          color: mealColor,
                          size: 18,
                        ),
                        onPressed: () => _logMeal(title),
                        padding: EdgeInsets.zero,
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

  IconData _getMealIcon(String meal) {
    switch (meal.toLowerCase()) {
      case 'breakfast':
        return Icons.wb_sunny_outlined;
      case 'lunch':
        return Icons.lunch_dining_outlined;
      case 'dinner':
        return Icons.dinner_dining_outlined;
      case 'snack':
        return Icons.cookie_outlined;
      default:
        return Icons.restaurant;
    }
  }

  Color getMealColor(String meal) {
    switch (meal.toLowerCase()) {
      case 'breakfast':
        return const Color(0xFF4A9B8E); // 青绿色
      case 'lunch':
        return const Color(0xFF6BB6A7); // 浅青绿
      case 'dinner':
        return const Color(0xFF2E7D6B); // 深青绿
      case 'snack':
        return const Color(0xFF8FD4C1); // 薄荷青
      default:
        return Colors.grey;
    }
  }

  /// 调试方法：测试自动调整功能
  Future<void> _testAutoAdjustment() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not found')),
      );
      return;
    }

    try {
      // 检查状态
      final status = await _autoAdjustmentService.debugAutoAdjustmentStatus(currentUser.userID);
      print('Debug status: $status');

      // 执行立即调整
      final result = await _autoAdjustmentService.executeNow(currentUser.userID);
      print('Test result: $result');

      // 如果调整成功，刷新页面数据
      if (result['success']) {
        await _loadTodayCalories();
        await _loadAdjustedTarget(); // 加载最新的调整后目标
        setState(() {
          // 触发UI更新
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test completed: ${result['success'] ? 'Success' : 'Failed'} - ${result['reason']}'),
          backgroundColor: result['success'] ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      print('Error testing auto adjustment: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}





























