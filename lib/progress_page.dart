import 'package:caloriecare/homepage.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/weight_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:caloriecare/profile_page.dart';
import 'package:caloriecare/session_service.dart';
import 'package:caloriecare/utils/weight_validator.dart';
import 'goal_achievement_page.dart';
import 'package:caloriecare/goal_achievement_service.dart';
import 'package:caloriecare/refresh_manager.dart';

class ProgressPage extends StatefulWidget {
  final UserModel? user;
  const ProgressPage({Key? key, this.user}) : super(key: key);

  @override
  _ProgressPageState createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> with TickerProviderStateMixin {
  late TabController _tabController;
  final WeightService _weightService = WeightService();
  final ScrollController _scrollController = ScrollController();
  
  // Data variables
  List<Map<String, dynamic>> _calorieData = [];
  List<Map<String, dynamic>> _weightData = [];
  List<Map<String, dynamic>> _allWeightData = []; // Store all weight data
  bool _isLoading = true;
  String _selectedView = 'Daily view';
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedMonth = DateTime.now();
  double _headerOpacity = 1.0;
  double _headerHeight = 1.0;
  
  // Weight chart variables
  String _selectedWeightPeriod = '1week';
  List<String> _weightPeriods = ['1week', '1month', '2mon', '3mon', '6mon'];
  DateTime? _weightChartStartDate;
  DateTime? _weightChartEndDate;
  
  // Timeline filter variables (synchronized with weight period)
  String _selectedTimelineFilter = 'Last 7 days';
  List<String> _timelineFilters = ['Last 7 days', 'Last 30 days', 'Last 2 months', 'Last 3 months', 'Last 6 months', 'All records'];
  
  // Weight record search and filter variables
  final TextEditingController _weightSearchController = TextEditingController();
  List<Map<String, dynamic>> _filteredWeightData = [];
  DateTime? _searchStartDate;
  DateTime? _searchEndDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Rebuild UI when tab changes
    });
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _weightSearchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final scrollOffset = _scrollController.offset;
    const maxScrollDistance = 100.0; // 滚动100像素后完全隐藏
    
    // 计算透明度：从1.0逐渐减少到0.0
    final newOpacity = (1.0 - (scrollOffset / maxScrollDistance)).clamp(0.0, 1.0);
    
    // 计算高度比例：从1.0逐渐减少到0.0
    final newHeight = (1.0 - (scrollOffset / maxScrollDistance)).clamp(0.0, 1.0);
    
    // 只有当值真正改变时才更新状态
    if ((newOpacity - _headerOpacity).abs() > 0.01 || (newHeight - _headerHeight).abs() > 0.01) {
      setState(() {
        _headerOpacity = newOpacity;
        _headerHeight = newHeight;
      });
    }
  }

  Future<void> _loadData() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await Future.wait([
        _loadCalorieData(),
        _loadWeightData(),
      ]);
    } catch (e) {
      print('Error loading data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCalorieData() async {
    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) return;
      final userId = currentUser.userID;
      
      if (_selectedView == 'Daily view') {
        final today = DateFormat('yyyy-MM-dd').format(_selectedDate);
        
        // Get calorie data for the selected date
        final query = await FirebaseFirestore.instance
            .collection('LogMeal')
            .where('UserID', isEqualTo: userId)
            .where('LogDate', isEqualTo: today)
            .get();

        // Check if there are any food logs for this date
        if (query.docs.isEmpty) {
          setState(() {
            _calorieData = []; // Empty data to trigger "no data" UI
          });
          return;
        }

        Map<String, int> mealCalories = {
          'Breakfast': 0,
          'Lunch': 0,
          'Dinner': 0,
          'Snack': 0,
        };

        int totalCalories = 0;
        for (var doc in query.docs) {
          final data = doc.data();
          final mealType = data['MealType'] ?? '';
          final calories = (data['TotalCalories'] ?? 0) as num;
          
          if (mealCalories.containsKey(mealType)) {
            mealCalories[mealType] = calories.toInt();
          }
          totalCalories += calories.toInt();
        }

        setState(() {
          _calorieData = [
            {'meal': 'Breakfast', 'calories': mealCalories['Breakfast']!},
            {'meal': 'Lunch', 'calories': mealCalories['Lunch']!},
            {'meal': 'Dinner', 'calories': mealCalories['Dinner']!},
            {'meal': 'Snacks', 'calories': mealCalories['Snack']!},
          ];
        });
      } else if (_selectedView == 'Monthly view') {
        // Get calorie data for the selected month
        final startOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
        final endOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
        
        final startDateStr = DateFormat('yyyy-MM-dd').format(startOfMonth);
        final endDateStr = DateFormat('yyyy-MM-dd').format(endOfMonth);
        
        final query = await FirebaseFirestore.instance
            .collection('LogMeal')
            .where('UserID', isEqualTo: userId)
            .get();

        // Filter by date range on client side
        final filteredDocs = query.docs.where((doc) {
          final logDate = doc.data()['LogDate'] as String?;
          if (logDate == null) return false;
          return logDate.compareTo(startDateStr) >= 0 && logDate.compareTo(endDateStr) <= 0;
        }).toList();

        Map<String, int> mealCalories = {
          'Breakfast': 0,
          'Lunch': 0,
          'Dinner': 0,
          'Snack': 0,
        };

        for (var doc in filteredDocs) {
          final data = doc.data();
          final mealType = data['MealType'] ?? '';
          final calories = (data['TotalCalories'] ?? 0) as num;
          
          if (mealCalories.containsKey(mealType)) {
            mealCalories[mealType] = mealCalories[mealType]! + calories.toInt();
          }
        }

        setState(() {
          _calorieData = [
            {'meal': 'Breakfast', 'calories': mealCalories['Breakfast']!},
            {'meal': 'Lunch', 'calories': mealCalories['Lunch']!},
            {'meal': 'Dinner', 'calories': mealCalories['Dinner']!},
            {'meal': 'Snacks', 'calories': mealCalories['Snack']!},
          ];
        });
      }
    } catch (e) {
      print('Error loading calorie data: $e');
    }
  }

  Future<void> _loadWeightData() async {
    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) return;
      final userId = currentUser.userID;
      
      // Get all weight records first
      _allWeightData = await _weightService.getWeightHistory(userId, limit: 100);
      
      // Filter based on selected period for chart
      DateTime startDate;
      final now = DateTime.now();
      
      switch (_selectedWeightPeriod) {
        case '1week':
          startDate = now.subtract(const Duration(days: 6));
          break;
        case '1month':
          startDate = DateTime(now.year, now.month - 1, now.day);
          break;
        case '2mon':
          startDate = DateTime(now.year, now.month - 2, now.day);
          break;
        case '3mon':
          startDate = DateTime(now.year, now.month - 3, now.day);
          break;
        case '6mon':
          startDate = DateTime(now.year, now.month - 6, now.day);
          break;
        default:
          startDate = now.subtract(const Duration(days: 6));
      }
      
      // Filter records for chart within the selected period
      final chartFilteredRecords = _allWeightData.where((record) {
        final recordDate = DateFormat('yyyy-MM-dd').parse(record['date']);
        return recordDate.isAfter(startDate) || recordDate.isAtSameMomentAs(startDate);
      }).toList();
      
      // Sort by date
      chartFilteredRecords.sort((a, b) {
        final dateA = DateFormat('yyyy-MM-dd').parse(a['date']);
        final dateB = DateFormat('yyyy-MM-dd').parse(b['date']);
        return dateA.compareTo(dateB);
      });

      // Apply timeline filter for display
      _applyTimelineFilter();
      
      // Save time range information for chart display
      _weightChartStartDate = startDate;
      _weightChartEndDate = now;
      
      print('Chart data dates: ${chartFilteredRecords.map((r) => r['date']).toList()}');
      print('Timeline data dates: ${_weightData.map((r) => r['date']).toList()}');
    } catch (e) {
      print('Error loading weight data: $e');
    }
  }

  void _applyTimelineFilter() {
    final now = DateTime.now();
    DateTime filterStartDate;
    
    switch (_selectedTimelineFilter) {
      case 'Last 7 days':
        filterStartDate = now.subtract(const Duration(days: 6));
        break;
      case 'Last 30 days':
        filterStartDate = DateTime(now.year, now.month - 1, now.day);
        break;
      case 'Last 2 months':
        filterStartDate = DateTime(now.year, now.month - 2, now.day);
        break;
      case 'Last 3 months':
        filterStartDate = DateTime(now.year, now.month - 3, now.day);
        break;
      case 'Last 6 months':
        filterStartDate = DateTime(now.year, now.month - 6, now.day);
        break;
      case 'All records':
        setState(() {
          _weightData = List.from(_allWeightData);
        });
        return;
      default:
        filterStartDate = now.subtract(const Duration(days: 6));
    }
    
    // Filter timeline data
    final timelineFilteredRecords = _allWeightData.where((record) {
      final recordDate = DateFormat('yyyy-MM-dd').parse(record['date']);
      return recordDate.isAfter(filterStartDate) || recordDate.isAtSameMomentAs(filterStartDate);
    }).toList();
    
    // Sort by date (most recent first for timeline)
    timelineFilteredRecords.sort((a, b) {
      final dateA = DateFormat('yyyy-MM-dd').parse(a['date']);
      final dateB = DateFormat('yyyy-MM-dd').parse(b['date']);
      return dateB.compareTo(dateA);
    });
    
    setState(() {
      _weightData = timelineFilteredRecords;
      _filteredWeightData = List.from(_weightData); // 初始化过滤数据
    });
  }

  void _changeDate(int days) {
    setState(() {
      if (_selectedView == 'Daily view') {
        _selectedDate = _selectedDate.add(Duration(days: days));
      } else if (_selectedView == 'Monthly view') {
        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + days, 1);
      }
    });
    _loadData();
  }

  void _toggleView() {
    setState(() {
      if (_selectedView == 'Daily view') {
        _selectedView = 'Monthly view';
      } else {
        _selectedView = 'Daily view';
      }
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Progress',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.grey.shade200,
                  Colors.grey.shade100,
                  Colors.grey.shade200,
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Enhanced Tab Bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _headerHeight > 0.1 ? 90 * _headerHeight : 0,
            child: Opacity(
              opacity: _headerOpacity,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5AA162), Color(0xFF7BB77E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5AA162).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey[600],
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  tabs: const [
                    Tab(text: 'Calories'),
                    Tab(text: 'Weight'),
                  ],
                ),
              ),
            ),
          ),

          // Enhanced Date Navigation (only for Calories tab)
          if (_tabController.index == 0) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: _headerHeight > 0.1 ? 140 * _headerHeight : 0,
              child: Opacity(
                opacity: _headerOpacity,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF5AA162).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: IconButton(
                                    onPressed: () => _changeDate(-1),
                                    icon: const Icon(
                                      Icons.chevron_left,
                                      color: Color(0xFF5AA162),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Text(
                                      _selectedView == 'Daily view'
                                          ? DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate)
                                          : DateFormat('MMMM yyyy').format(_selectedMonth),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black87,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF5AA162).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: IconButton(
                                    onPressed: () => _changeDate(1),
                                    icon: const Icon(
                                      Icons.chevron_right,
                                      color: Color(0xFF5AA162),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        if (_selectedView != 'Daily view') {
                                          _toggleView();
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: _selectedView == 'Daily view'
                                              ? Colors.white
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: _selectedView == 'Daily view'
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.1),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Text(
                                          'Daily',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _selectedView == 'Daily view'
                                                ? const Color(0xFF5AA162)
                                                : Colors.grey[600],
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        if (_selectedView != 'Monthly view') {
                                          _toggleView();
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: _selectedView == 'Monthly view'
                                              ? Colors.white
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: _selectedView == 'Monthly view'
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.1),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Text(
                                          'Monthly',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _selectedView == 'Monthly view'
                                                ? const Color(0xFF5AA162)
                                                : Colors.grey[600],
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
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
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCaloriesTab(),
                _buildWeightTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        onTap: (index) async {
          if (index == 0) {
            UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
            if (currentUser != null) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => HomePage(user: currentUser)),
                (route) => false,
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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Progress'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildCaloriesTab() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5AA162)),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading your progress...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Enhanced Empty State
    if (_calorieData.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF5AA162).withOpacity(0.1),
                        const Color(0xFF7BB77E).withOpacity(0.1),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.restaurant_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _selectedView == 'Daily view' 
                      ? 'No meals logged today'
                      : 'No meals this month',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _selectedView == 'Daily view'
                      ? 'Start tracking your nutrition journey'
                      : 'No meals were logged during this month',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_selectedView == 'Daily view') ...[
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5AA162), Color(0xFF7BB77E)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF5AA162).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () => _navigateToFoodLogging(),
                      icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
                      label: const Text(
                        'Log Your First Meal',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return FutureBuilder<int>(
      future: _selectedView == 'Daily view' 
          ? _getCalorieGoalForDate(_selectedDate)
          : _getMonthlyCalorieGoal(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final goal = snapshot.data!;
        final totalCalories = _calorieData.fold<int>(0, (total, item) => total + (item['calories'] as int));
        final netCalories = totalCalories;

        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Enhanced Pie Chart Container
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'Calorie Distribution',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 280,
                      child: PieChart(
                        PieChartData(
                          sections: _calorieData.map((data) {
                            final calories = data['calories'] as int;
                            final percentage = totalCalories > 0 ? (calories / totalCalories * 100) : 0;
                            
                            return PieChartSectionData(
                              value: calories.toDouble(),
                              title: '${percentage.toStringAsFixed(0)}%',
                              color: _getMealColor(data['meal']),
                              radius: 90,
                              titleStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              badgeWidget: percentage > 8 ? null : Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: _getMealColor(data['meal']),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${percentage.toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                          centerSpaceRadius: 50,
                          sectionsSpace: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Enhanced Legend
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Meal Breakdown',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._calorieData.map((data) {
                      final calories = data['calories'] as int;
                      final percentage = totalCalories > 0 ? (calories / totalCalories * 100) : 0;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _getMealColor(data['meal']).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _getMealColor(data['meal']).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: _getMealColor(data['meal']),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                data['meal'],
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${percentage.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _getMealColor(data['meal']),
                                  ),
                                ),
                                Text(
                                  '${calories} cal',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Enhanced Summary
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF5AA162).withOpacity(0.1),
                      const Color(0xFF7BB77E).withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF5AA162).withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildEnhancedSummaryRow('Total Calories', totalCalories.toString(), Icons.local_fire_department),
                    _buildEnhancedSummaryRow('Net Calories', netCalories.toString(), Icons.trending_up),
                    _buildEnhancedSummaryRow('Goal', goal.toString(), Icons.flag, isGoal: true),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeightTab() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5AA162)),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading weight data...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (_allWeightData.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF5AA162).withOpacity(0.1),
                        const Color(0xFF7BB77E).withOpacity(0.1),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.monitor_weight_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No weight data available for ${_getPeriodDisplayName(_selectedWeightPeriod).toLowerCase()}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Start tracking your weight progress or try selecting a different time period',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5AA162), Color(0xFF7BB77E)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5AA162).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _showAddWeightDialog,
                    icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
                    label: const Text(
                      'Add Weight Record',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Enhanced Weight Period Selector with Add Button
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Time Period',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5AA162), Color(0xFF7BB77E)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5AA162).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: _showAddWeightDialog,
                        icon: const Icon(Icons.add, color: Colors.white),
                        iconSize: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _weightPeriods.map((period) {
                      final isSelected = _selectedWeightPeriod == period;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedWeightPeriod = period;
                            // 同步时间过滤器
                            _selectedTimelineFilter = _getCorrespondingTimelineFilter(period);
                          });
                          _loadWeightData();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? const LinearGradient(
                                    colors: [Color(0xFF5AA162), Color(0xFF7BB77E)],
                                  )
                                : null,
                            color: isSelected ? null : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF5AA162).withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            _getPeriodDisplayName(period),
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          
          // Enhanced Weight Progress Chart
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Weight Progress',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 300,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: 6,
                      minY: _getMinWeight(),
                      maxY: _getMaxWeight(),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        drawHorizontalLine: true,
                        horizontalInterval: _getWeightInterval(),
                        verticalInterval: 1,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 1,
                          );
                        },
                        getDrawingVerticalLine: (value) {
                          return FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 1,
                          );
                        },
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 50,
                            interval: _getWeightInterval(),
                            getTitlesWidget: (value, meta) {
                              return Container(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  '${value.toInt()}kg',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: _getTimeInterval(),
                            getTitlesWidget: (value, meta) {
                              if (_weightChartStartDate != null && _weightChartEndDate != null) {
                                final daysDiff = _weightChartEndDate!.difference(_weightChartStartDate!).inDays;
                                
                                if (value >= 0 && value <= 6) {
                                  final dateIndex = (value * daysDiff / 6).round();
                                  final date = _weightChartStartDate!.add(Duration(days: dateIndex));
                                  return Container(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      DateFormat('dd/MM').format(date),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                }
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _generateChartSpots(),
                          isCurved: true,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF5AA162), Color(0xFF7BB77E)],
                          ),
                          barWidth: 4,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) {
                              return FlDotCirclePainter(
                                radius: 6,
                                color: Colors.white,
                                strokeWidth: 3,
                                strokeColor: const Color(0xFF5AA162),
                              );
                            },
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF5AA162).withOpacity(0.1),
                                const Color(0xFF7BB77E).withOpacity(0.05),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
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

          const SizedBox(height: 24),

          // Enhanced Timeline Filter
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Weight Records',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5AA162).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedTimelineFilter,
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedTimelineFilter = newValue;
                              // 同步图表时间段
                              _selectedWeightPeriod = _getCorrespondingWeightPeriod(newValue);
                            });
                            _loadWeightData(); // 重新加载数据以同步图表
                          }
                        },
                        underline: Container(),
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          color: const Color(0xFF5AA162),
                          size: 20,
                        ),
                        style: const TextStyle(
                          color: Color(0xFF5AA162),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        items: _timelineFilters.map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Search and Filter Bar
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: TextField(
                          controller: _weightSearchController,
                          onChanged: (value) => _filterWeightRecords(),
                          decoration: InputDecoration(
                            hintText: 'Search by date or weight...',
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                            prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: (_searchStartDate != null || _searchEndDate != null)
                            ? const Color(0xFF5AA162)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (_searchStartDate != null || _searchEndDate != null)
                              ? const Color(0xFF5AA162)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _showDateRangeFilter,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              Icons.date_range,
                              color: (_searchStartDate != null || _searchEndDate != null)
                                  ? Colors.white
                                  : Colors.grey.shade600,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_weightSearchController.text.isNotEmpty || _searchStartDate != null || _searchEndDate != null)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _clearSearchFilters,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                Icons.clear,
                                color: Colors.grey.shade600,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Enhanced weight entries
                if (_filteredWeightData.isEmpty && _weightData.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off,
                          color: Colors.grey.shade400,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No records match your search',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try adjusting your search terms or date range',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                if (_filteredWeightData.isEmpty && _weightData.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.monitor_weight_outlined,
                          color: Colors.grey.shade400,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No weight records found',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start tracking your weight to see records here',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                ..._filteredWeightData.map((record) {
                  final date = DateFormat('dd/MM/yyyy').format(
                    DateFormat('yyyy-MM-dd').parse(record['date'])
                  );
                  final weight = record['weight'];
                  String weightStr;
                  if (weight is int) {
                    weightStr = '${weight}kg';
                  } else if (weight is double) {
                    weightStr = '${weight.toStringAsFixed(1)}kg';
                  } else {
                    weightStr = '${weight}kg';
                  }

                  return GestureDetector(
                    onTap: () => _showEditWeightDialog(record),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF5AA162).withOpacity(0.05),
                            const Color(0xFF7BB77E).withOpacity(0.02),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF5AA162).withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF5AA162), Color(0xFF7BB77E)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.monitor_weight,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  weightStr,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  date,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.edit_outlined,
                            color: const Color(0xFF5AA162),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedSummaryRow(String label, String value, IconData icon, {bool isGoal = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isGoal 
            ? const Color(0xFF5AA162).withOpacity(0.1)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGoal 
              ? const Color(0xFF5AA162).withOpacity(0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isGoal 
                  ? const Color(0xFF5AA162)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: isGoal ? Colors.white : Colors.grey.shade600,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isGoal ? const Color(0xFF5AA162) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Color _getMealColor(String meal) {
    switch (meal.toLowerCase()) {
      case 'breakfast':
        return const Color(0xFF4A9B8E);
      case 'lunch':
        return const Color(0xFF6BB6A7);
      case 'dinner':
        return const Color(0xFF2E7D6B);
      case 'snacks':
        return const Color(0xFF8FD4C1);
      default:
        return Colors.grey;
    }
  }
  
  double _getMinWeight() {
    if (_weightData.isEmpty) {
      // 当没有数据时，返回一个合理的默认范围下限
      // 基于用户profile或全局设置，这里使用55kg作为默认下限
      return 55.0;
    }
    
    final weights = _weightData.map((record) {
      final weight = record['weight'];
      if (weight is int) {
        return weight.toDouble();
      } else if (weight is double) {
        return weight;
      } else {
        return 65.0; // 默认值
      }
    }).toList();
    
    final minWeight = weights.reduce((a, b) => a < b ? a : b);
    // 最小值比实际数据的最低值再低5kg，但不低于30kg，并确保是5的倍数
    final targetMin = minWeight - 5;
    // 确保最小值不低于30kg，最大值不超过minWeight-1
    final minLimit = 30.0;
    final maxLimit = minWeight - 1;
    final calculatedMin = targetMin.clamp(minLimit, maxLimit > minLimit ? maxLimit : minLimit);
    final flooredMin = calculatedMin.floor();
    // 向下取整到最近的5的倍数
    return (flooredMin ~/ 5 * 5).toDouble();
  }
  
  double _getMaxWeight() {
    if (_weightData.isEmpty) {
      // 当没有数据时，返回一个合理的默认范围上限
      // 与下限相对应，这里使用75kg作为默认上限
      return 75.0;
    }
    
    final weights = _weightData.map((record) {
      final weight = record['weight'];
      if (weight is int) {
        return weight.toDouble();
      } else if (weight is double) {
        return weight;
      } else {
        return 65.0; // 默认值
      }
    }).toList();
    
    final maxWeight = weights.reduce((a, b) => a > b ? a : b);
    // 最大值比实际数据的最高值再高5kg，但不高于150kg，并确保是5的倍数
    final calculatedMax = (maxWeight + 5).clamp(maxWeight + 1, 150.0);
    final ceiledMax = calculatedMax.ceil();
    // 向上取整到最近的5的倍数
    return ((ceiledMax + 4) ~/ 5 * 5).toDouble();
  }
  
  double _getWeightInterval() {
    final minY = _getMinWeight();
    final maxY = _getMaxWeight();
    final range = maxY - minY;
    
    // 使用更安全的方法计算间隔
    if (range <= 0.1) {
      return 5.0; // 如果体重范围太小，使用5kg作为默认间隔
    }
    
    // 计算合适的间隔，确保显示4-5个标签，间隔为5的倍数
    final interval = (range / 4).ceil().toDouble();
    // 确保间隔是5的倍数，最小为5
    return (interval < 5 ? 5 : ((interval + 2) ~/ 5 * 5)).toDouble();
  }
  
  double _getTimeInterval() {
    // 如果有时间范围信息，使用固定的7个时间点
    if (_weightChartStartDate != null && _weightChartEndDate != null) {
      return 1.0; // 固定间隔，显示7个时间点 (0, 1, 2, 3, 4, 5, 6)
    }
    
    if (_weightData.isEmpty) return 1.0;
    
    // 使用更安全的方法计算时间间隔
    if (_weightData.length <= 1) {
      return 1.0; // 如果只有一个数据点，使用默认间隔
    }
    
    // 根据数据点数量调整间隔，确保显示7个时间点
    final totalPoints = _weightData.length;
    if (totalPoints <= 7) {
      return 1.0; // 如果数据点少于等于7个，每个点都显示
    } else {
      return (totalPoints - 1) / 6.0; // 显示7个时间点
    }
  }
  
  // 显示添加体重对话框
  void _showAddWeightDialog() {
    DateTime selectedDate = DateTime.now();
    final TextEditingController weightController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.add_circle, color: Color(0xFF5AA162)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Add Weight Record',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Date Picker
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Select Date'),
                    subtitle: Text(
                      DateFormat('dd/MM/yyyy').format(selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Weight Input
                  TextField(
                    controller: weightController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Weight (kg)',
                      hintText: WeightValidator.getWeightRangeHint(),
                      helperText: 'Please enter a reasonable weight value',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.monitor_weight),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // 验证体重输入
                    final validationResult = WeightValidator.validateWeightString(weightController.text);
                    if (!validationResult.isValid) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(validationResult.errorMessage),
                              if (validationResult.suggestion.isNotEmpty)
                                Text(
                                  validationResult.suggestion,
                                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                            ],
                          ),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                      return;
                    }
                    
                    final weight = double.parse(weightController.text);
                    // 先关闭对话框
                    Navigator.of(context).pop();
                    // 然后添加体重记录
                    await _addWeightRecord(selectedDate, weight);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5AA162),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 添加体重记录
  Future<void> _addWeightRecord(DateTime date, double weight) async {
    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final userId = currentUser.userID;
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      final result = await _weightService.recordWeightForDate(userId, weight, dateStr);
      
      print('=== PROGRESS PAGE: _addWeightRecord ===');
      print('Weight service result: $result');
      print('Success: ${result['success']}');
      print('Goal achieved: ${result['goalAchieved']}');
      
      if (result['success']) {
        // 重新加载数据
        _loadWeightData();
        
        // Check if goal was achieved
        if (result['goalAchieved'] == true) {
          print('🎉 Goal achieved! Navigating to Goal Achievement Page...');
          // Navigate to goal achievement page
          final updatedUser = await SessionService.getUserSession();
          print('Updated user: ${updatedUser?.goal}, TDEE: ${updatedUser?.tdee}');
          print('Updated user details: ${updatedUser?.userID}, ${updatedUser?.username}');
          
          if (updatedUser == null) {
            print('❌ Updated user is null, cannot navigate');
            return;
          }
          
          try {
            print('🚀 Starting navigation to Goal Achievement Page...');
            print('Context: $context');
            print('Navigator: ${Navigator.of(context)}');
            
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) {
                  print('Building Goal Achievement Page...');
                  return GoalAchievementPage(
                    achievedWeight: weight,
                    newTDEE: updatedUser.tdee,
                    user: updatedUser,
                  );
                },
              ),
            );
            print('✅ Navigation to Goal Achievement Page completed');
          } catch (e) {
            print('❌ Error during navigation: $e');
            print('Error stack trace: ${StackTrace.current}');
          }
        } else {
          print('❌ Goal not achieved, showing success message');
          // 触发刷新
          RefreshManagerHelper.refreshAfterWeightRecord();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Weight record added for ${DateFormat('dd/MM/yyyy').format(date)}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${result['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding weight record: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 生成图表数据点
  List<FlSpot> _generateChartSpots() {
    if (_weightData.isEmpty) return [];
    
    // 如果有时间范围信息，根据时间范围生成spots
    if (_weightChartStartDate != null && _weightChartEndDate != null) {
      final daysDiff = _weightChartEndDate!.difference(_weightChartStartDate!).inDays;
      
      // 生成spots - 为每个真实数据点计算正确的X轴位置
      final List<FlSpot> spots = [];
      for (final record in _weightData) {
        final recordDate = DateFormat('yyyy-MM-dd').parse(record['date']);
        final daysFromStart = recordDate.difference(_weightChartStartDate!).inDays;
        
        // 计算在7个时间点中的位置
        if (daysDiff > 0) {
          final xPosition = (daysFromStart * 6 / daysDiff).clamp(0.0, 6.0);
          final weight = record['weight'];
          double weightValue;
          if (weight is int) {
            weightValue = weight.toDouble();
          } else if (weight is double) {
            weightValue = weight;
          } else {
            weightValue = 65.0;
          }
          
          spots.add(FlSpot(xPosition, weightValue));
          print('Added spot: date=${record['date']}, x=$xPosition, weight=$weightValue');
        }
      }
      
      // 按X轴位置排序，确保线条连接正确
      spots.sort((a, b) => a.x.compareTo(b.x));
      print('Sorted spots: ${spots.map((spot) => '(${spot.x}, ${spot.y})').join(', ')}');
      
      return spots;
    }
    
    // 如果没有时间范围信息，使用原来的逻辑
    return _weightData.asMap().entries.map((entry) {
      final weight = entry.value['weight'];
      double weightValue;
      if (weight is int) {
        weightValue = weight.toDouble();
      } else if (weight is double) {
        weightValue = weight;
      } else {
        weightValue = 65.0;
      }
      return FlSpot(entry.key.toDouble(), weightValue);
    }).toList();
  }

  // 生成时间范围内的数据点
  Future<List<Map<String, dynamic>>> _generateTimeBasedData() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    final userId = currentUser?.userID ?? '';
    final List<Map<String, dynamic>> generatedData = [];
    
    // 使用当前日期作为结束日期
    final DateTime endDate = DateTime.now();
    
    // 根据选择的时间范围计算实际的时间跨度
    DateTime actualStartDate;
    DateTime actualEndDate;
    
    switch (_selectedWeightPeriod) {
      case '1week':
        actualStartDate = endDate.subtract(const Duration(days: 6));
        actualEndDate = endDate;
        break;
      case '1month':
        actualStartDate = DateTime(endDate.year, endDate.month - 1, endDate.day);
        actualEndDate = endDate;
        break;
      case '2mon':
        actualStartDate = DateTime(endDate.year, endDate.month - 2, endDate.day);
        actualEndDate = endDate;
        break;
      case '3mon':
        actualStartDate = DateTime(endDate.year, endDate.month - 3, endDate.day);
        actualEndDate = endDate;
        break;
      case '6mon':
        actualStartDate = DateTime(endDate.year, endDate.month - 6, endDate.day);
        actualEndDate = endDate;
        break;
      default:
        actualStartDate = endDate.subtract(const Duration(days: 6));
        actualEndDate = endDate;
    }
    
    final int daysDiff = actualEndDate.difference(actualStartDate).inDays;
    
    // 获取现有的体重数据作为基准
    double baseWeight = 65.0; // 默认基准体重
    if (_weightData.isNotEmpty) {
      final weight = _weightData.first['weight'];
      if (weight is int) {
        baseWeight = weight.toDouble();
      } else if (weight is double) {
        baseWeight = weight;
      }
    }
    
    // 生成完整时间范围的数据点
    for (int i = 0; i <= daysDiff; i++) {
      final date = actualStartDate.add(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      // 添加一些随机变化，但保持在合理范围内
      final randomVariation = (i % 3 - 1) * 0.1; // -0.1, 0, 0.1
      final weight = baseWeight + randomVariation;
      
      generatedData.add({
        'weight': weight,
        'date': dateStr,
      });
    }
    
    print('Generated data from ${DateFormat('dd/MM').format(actualStartDate)} to ${DateFormat('dd/MM').format(actualEndDate)}');
    print('Total data points: ${generatedData.length}');
    
    return generatedData;
  }

  // Add method to get monthly calorie goal
  Future<int> _getMonthlyCalorieGoal() async {
    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final dailyGoal = await _getCalorieGoalForDate(_selectedMonth);
    return dailyGoal * daysInMonth;
  }

  // Add navigation method
  void _navigateToFoodLogging() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser != null) {
      // Navigate to food logging page with selected date
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            user: currentUser,
            initialSelectedDate: _selectedDate, // Pass the selected date
          ),
        ),
      );
      
      // Refresh data when returning
      _loadData();
    }
  }

  // Add method to get period display name
  String _getPeriodDisplayName(String period) {
    switch (period) {
      case '1week':
        return '1 Week';
      case '1month':
        return '1 Month';
      case '2mon':
        return '2 Months';
      case '3mon':
        return '3 Months';
      case '6mon':
        return '6 Months';
      default:
        return period;
    }
  }
  
  // Search and filter weight records
  void _filterWeightRecords() {
    final searchText = _weightSearchController.text.toLowerCase();
    List<Map<String, dynamic>> filtered = List.from(_weightData);
    
    // Apply text search (by date or weight)
    if (searchText.isNotEmpty) {
      filtered = filtered.where((record) {
        final date = record['date'] as String;
        final weight = record['weight'].toString();
        final formattedDate = DateFormat('dd/MM/yyyy').format(
          DateFormat('yyyy-MM-dd').parse(date)
        );
        
        return date.toLowerCase().contains(searchText) ||
               weight.toLowerCase().contains(searchText) ||
               formattedDate.toLowerCase().contains(searchText);
      }).toList();
    }
    
    // Apply date range filter
    if (_searchStartDate != null && _searchEndDate != null) {
      filtered = filtered.where((record) {
        final recordDate = DateFormat('yyyy-MM-dd').parse(record['date']);
        return (recordDate.isAfter(_searchStartDate!) || recordDate.isAtSameMomentAs(_searchStartDate!)) &&
               (recordDate.isBefore(_searchEndDate!) || recordDate.isAtSameMomentAs(_searchEndDate!));
      }).toList();
    }
    
    setState(() {
      _filteredWeightData = filtered;
    });
  }
  
  void _clearSearchFilters() {
    setState(() {
      _weightSearchController.clear();
      _searchStartDate = null;
      _searchEndDate = null;
      _filteredWeightData = List.from(_weightData);
    });
  }
  
  void _showDateRangeFilter() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        DateTime? startDate = _searchStartDate;
        DateTime? endDate = _searchEndDate;
        
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.date_range, color: const Color(0xFF5AA162)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Filter by Date Range',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Start Date'),
                    subtitle: Text(
                      startDate != null
                          ? DateFormat('dd/MM/yyyy').format(startDate!)
                          : 'Select start date',
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          startDate = picked;
                        });
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('End Date'),
                    subtitle: Text(
                      endDate != null
                          ? DateFormat('dd/MM/yyyy').format(endDate!)
                          : 'Select end date',
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate ?? DateTime.now(),
                        firstDate: startDate ?? DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          endDate = picked;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    this.setState(() {
                      _searchStartDate = startDate;
                      _searchEndDate = endDate;
                    });
                    Navigator.of(context).pop();
                    _filterWeightRecords();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5AA162),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 获取对应的时间过滤器
  String _getCorrespondingTimelineFilter(String weightPeriod) {
    switch (weightPeriod) {
      case '1week':
        return 'Last 7 days';
      case '1month':
        return 'Last 30 days';
      case '2mon':
        return 'Last 2 months';
      case '3mon':
        return 'Last 3 months';
      case '6mon':
        return 'Last 6 months';
      default:
        return 'Last 7 days';
    }
  }

  // 获取对应的体重时间段
  String _getCorrespondingWeightPeriod(String timelineFilter) {
    switch (timelineFilter) {
      case 'Last 7 days':
        return '1week';
      case 'Last 30 days':
        return '1month';
      case 'Last 2 months':
        return '2mon';
      case 'Last 3 months':
        return '3mon';
      case 'Last 6 months':
        return '6mon';
      case 'All records':
        return '6mon'; // 默认显示6个月的图表
      default:
        return '1week';
    }
  }

  // Add method to show edit weight dialog
  void _showEditWeightDialog(Map<String, dynamic> record) {
    DateTime selectedDate = DateFormat('yyyy-MM-dd').parse(record['date']);
    final TextEditingController weightController = TextEditingController();
    weightController.text = record['weight'].toString();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.edit, color: Color(0xFF5AA162)),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Edit Weight Record',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Date Picker
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Date'),
                    subtitle: Text(
                      DateFormat('dd/MM/yyyy').format(selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Weight Input
                  TextField(
                    controller: weightController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Weight (kg)',
                      hintText: WeightValidator.getWeightRangeHint(),
                      helperText: 'Please enter a reasonable weight value',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.monitor_weight),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // 验证体重输入
                    final validationResult = WeightValidator.validateWeightString(weightController.text);
                    if (!validationResult.isValid) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(validationResult.errorMessage),
                              if (validationResult.suggestion.isNotEmpty)
                                Text(
                                  validationResult.suggestion,
                                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                            ],
                          ),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                      return;
                    }
                    
                    final weight = double.parse(weightController.text);
                    await _updateWeightRecord(record, selectedDate, weight);
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5AA162),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Add method to update weight record
  Future<void> _updateWeightRecord(Map<String, dynamic> record, DateTime date, double weight) async {
    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final userId = currentUser.userID;
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      // Update the weight record
      final result = await _weightService.updateWeightRecord(userId, record['date'], weight, dateStr);
      
      // Reload data
      _loadWeightData();
      
      if (result['success'] == true) {
        print('=== Progress Page Weight Update Result ===');
        print('Success: ${result['success']}');
        print('Goal Achieved: ${result['goalAchieved']}');
        print('Weight: ${result['weight']}');
        
        if (result['goalAchieved'] == true) {
          print('🎉 Navigating to Goal Achievement Page...');
          // Navigate to goal achievement page
          final updatedUser = await SessionService.getUserSession();
          print('Updated user goal: ${updatedUser?.goal}');
          print('Updated user TDEE: ${updatedUser?.tdee}');
          
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => GoalAchievementPage(
                achievedWeight: weight,
                newTDEE: updatedUser?.tdee ?? 2000,
                user: updatedUser,
              ),
            ),
          );
        } else {
          // 触发刷新
          RefreshManagerHelper.refreshAfterWeightRecord();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Weight record updated for ${DateFormat('dd/MM/yyyy').format(date)}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${result['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error updating weight record: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update weight record'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Add method to get adjusted calorie goal for selected date
  Future<int> _getCalorieGoalForDate(DateTime date) async {
    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) return 2000;
      
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      // Check for active calorie adjustment on the selected date
      final adjustmentQuery = await FirebaseFirestore.instance
          .collection('CalorieAdjustment')
          .where('UserID', isEqualTo: currentUser.userID)
          .where('AdjustDate', isEqualTo: dateStr)
          .where('IsActive', isEqualTo: true)
          .get();
      
      if (adjustmentQuery.docs.isNotEmpty) {
        // Use adjusted target calories
        return (adjustmentQuery.docs.first.data()['AdjustTargetCalories'] ?? currentUser.dailyCalorieTarget).toInt();
      } else {
 
       // Use default daily calorie target
        return (currentUser.dailyCalorieTarget ?? 2000).toInt();
      }
    } catch (e) {
      print('Error getting calorie goal: $e');
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      return (currentUser?.dailyCalorieTarget ?? 2000).toInt();
    }
  }
}








