import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/homepage.dart';
import 'package:caloriecare/progress_page.dart';
import 'package:caloriecare/invite_supervisor_page.dart';
import 'package:caloriecare/streak_service.dart'; // Added import for StreakService
import 'package:caloriecare/profile_page.dart'; // Added import for ProfilePage
import 'package:caloriecare/session_service.dart'; // Added import for SessionService
import 'custom_message_page.dart'; // Add import for CustomMessagePage
import 'notification_service.dart'; // Add import for NotificationService
import 'global_notification_manager.dart'; // Add import for GlobalNotificationManager

// Model for displaying supervision details
class SupervisionDetail {
  final String supervisionId;
  final int streak;
  final String otherUserName;
  final String otherUserGender; // Add gender field
  final bool hasLoggedToday; // Add today's log status for display
  final bool otherUserLoggedToday; // Add other user's log status for reminder logic

  SupervisionDetail({
    required this.supervisionId,
    required this.streak,
    required this.otherUserName,
    required this.otherUserGender, // Add gender parameter
    required this.hasLoggedToday, // Add today's log status parameter for display
    required this.otherUserLoggedToday, // Add other user's log status parameter for reminder
  });
}

class StreakCalendarPage extends StatefulWidget {
  final UserModel? user;
  const StreakCalendarPage({Key? key, required this.user}) : super(key: key);

  @override
  _StreakCalendarPageState createState() => _StreakCalendarPageState();
}

class _StreakCalendarPageState extends State<StreakCalendarPage> with TickerProviderStateMixin {
  late TabController _tabController;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Set<DateTime> _loggedDays = {};
  int _currentStreak = 0;
  bool _isLoading = true;
  bool _isSupervisionLoading = true;
  List<SupervisionDetail> _supervisions = [];
  bool _currentUserLoggedToday = false; // Add this field

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedDay = DateTime.now();
    _fetchStreakAndLogs();
    _fetchSupervisions();
    _checkCurrentUserLoggedToday(); // Add this call
  }

  // Add this method to check if current user logged today
  Future<void> _checkCurrentUserLoggedToday() async {
    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) return;

      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      final todayLogQuery = await FirebaseFirestore.instance
          .collection('LogMeal')
          .where('UserID', isEqualTo: currentUser.userID)
          .where('LogDate', isEqualTo: todayStr)
          .get();

      setState(() {
        _currentUserLoggedToday = todayLogQuery.docs.isNotEmpty;
      });
    } catch (e) {
      print('Error checking current user log status: $e');
    }
  }

  Future<void> _loadUserData() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser != null) {
      _fetchStreakAndLogs();
      _fetchSupervisions();
    } else {
      setState(() {
        _isLoading = false;
        _isSupervisionLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchSupervisions() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) {
      setState(() => _isSupervisionLoading = false);
      return;
    }
    final currentUserId = currentUser.userID;
    final db = FirebaseFirestore.instance;

    try {
      final userSupervisionsQuery = await db.collection('SupervisionList').where('UserID', isEqualTo: currentUserId).get();
      
      if (userSupervisionsQuery.docs.isEmpty) {
        setState(() {
          _supervisions = [];
          _isSupervisionLoading = false;
        });
        return;
      }
      
      final supervisionIds = userSupervisionsQuery.docs.map((doc) => doc['SupervisionID'] as String).toList();

      if (supervisionIds.isEmpty) {
         setState(() {
          _supervisions = [];
          _isSupervisionLoading = false;
        });
        return;
      }

      // Only get accepted supervisions
      final supervisionsQuery = await db.collection('Supervision')
          .where('SupervisionID', whereIn: supervisionIds)
          .where('Status', isEqualTo: 'accepted')
          .get();
      
      if (supervisionsQuery.docs.isEmpty) {
        setState(() {
          _supervisions = [];
          _isSupervisionLoading = false;
        });
        return;
      }

      final supervisionDataMap = {for (var doc in supervisionsQuery.docs) doc['SupervisionID'] as String: doc.data()};
      final acceptedSupervisionIds = supervisionsQuery.docs.map((doc) => doc['SupervisionID'] as String).toList();

      final allPairsQuery = await db.collection('SupervisionList')
          .where('SupervisionID', whereIn: acceptedSupervisionIds)
          .get();
      
      final allUserIds = allPairsQuery.docs.map((doc) => doc['UserID'] as String).toSet().toList();

      // Get user data
      final usersMap = <String, Map<String, dynamic>>{};
      for (String userId in allUserIds) {
        final userQuery = await db.collection('User').where('UserID', isEqualTo: userId).get();
        if (userQuery.docs.isNotEmpty) {
          usersMap[userId] = userQuery.docs.first.data();
        }
      }

      // Get supervisor streak data from Supervision collection
      final supervisionStreakMap = <String, int>{};
      final supervisionLoggedTodayMap = <String, bool>{};
      final streakService = StreakService();
      
      // Get today's date string
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      for (var doc in supervisionsQuery.docs) {
        final supervisionId = doc['SupervisionID'] as String;
        
        // Check and reset supervisor streak if needed
        final updatedStreak = await streakService.checkAndResetSupervisorStreakIfNeeded(supervisionId);
        supervisionStreakMap[supervisionId] = updatedStreak;
        
        // Check if supervision logged today based on Supervision's LastLoggedDate
        final lastLoggedDate = doc.data()['LastLoggedDate'];
        supervisionLoggedTodayMap[supervisionId] = lastLoggedDate == todayStr;
      }

      final Map<String, List<String>> supervisionUserPairs = {};
      for (var doc in allPairsQuery.docs) {
        final data = doc.data();
        final supervisionId = data['SupervisionID'] as String;
        final userId = data['UserID'] as String;
        supervisionUserPairs.putIfAbsent(supervisionId, () => []).add(userId);
      }

      final List<SupervisionDetail> details = [];
      for (var entry in supervisionUserPairs.entries) {
        final supervisionId = entry.key;
        final userIds = entry.value;
        final otherUserId = userIds.firstWhere((id) => id != currentUserId, orElse: () => '');
        final supervisionData = supervisionDataMap[supervisionId];
        final otherUserData = usersMap[otherUserId];

        if (supervisionData != null && otherUserData != null) {
          // Use Supervision's LastLoggedDate for streak display
          final supervisionLastLoggedDate = supervisionData['LastLoggedDate'];
          final hasLoggedToday = supervisionLastLoggedDate == todayStr;
          
          // Check if the other user logged today by checking their StreakRecord for reminder logic
          bool otherUserLoggedToday = false;
          try {
            final otherUserStreakQuery = await db
                .collection('StreakRecord')
                .where('UserID', isEqualTo: otherUserId)
                .limit(1)
                .get();
            
            if (otherUserStreakQuery.docs.isNotEmpty) {
              final otherUserStreakData = otherUserStreakQuery.docs.first.data();
              final otherUserLastLoggedDate = otherUserStreakData['LastLoggedDate'] as String?;
              otherUserLoggedToday = otherUserLastLoggedDate == todayStr;
            }
          } catch (e) {
            print('Error checking other user streak record: $e');
          }

          details.add(SupervisionDetail(
            supervisionId: supervisionId,
            streak: supervisionStreakMap[supervisionId] ?? 0,
            otherUserName: otherUserData['UserName'] ?? otherUserData['username'] ?? 'Unknown User',
            otherUserGender: otherUserData['Gender'] ?? otherUserData['gender'] ?? 'male',
            hasLoggedToday: hasLoggedToday, // Use Supervision's LastLoggedDate for display
            otherUserLoggedToday: otherUserLoggedToday, // Use other user's StreakRecord for reminder logic
          ));
        }
      }

      setState(() {
        _supervisions = details;
        _isSupervisionLoading = false;
      });
    } catch (e) {
      print('Error fetching supervisions: $e');
      setState(() {
        _isSupervisionLoading = false;
      });
    }
  }

  Future<void> _fetchStreakAndLogs() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    if (currentUser == null || currentUser.userID.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    final userID = currentUser.userID;

    // First check if streak needs to be reset
    final streakService = StreakService();
    await streakService.checkAndResetStreakIfNeeded(userID);

    // Fetch streak record
    final streakQuery = await FirebaseFirestore.instance
        .collection('StreakRecord')
        .where('UserID', isEqualTo: userID)
        .limit(1)
        .get();

    if (streakQuery.docs.isNotEmpty) {
      _currentStreak = streakQuery.docs.first.data()['CurrentStreakDays'] ?? 0;
    }

    // Fetch all log dates for the user
    final logsQuery = await FirebaseFirestore.instance
        .collection('LogMeal')
        .where('UserID', isEqualTo: userID)
        .get();

    final Set<DateTime> loggedDays = {};
    for (var doc in logsQuery.docs) {
      final logDateStr = doc.data()['LogDate'];
      if (logDateStr != null) {
        try {
          final logDate = DateFormat('yyyy-MM-dd').parse(logDateStr);
          loggedDays.add(DateTime.utc(logDate.year, logDate.month, logDate.day));
        } catch (e) {
          print("Error parsing date: $logDateStr. Error: $e");
        }
      }
    }

    setState(() {
      _loggedDays = loggedDays;
      _isLoading = false;
    });
  }

  List<DateTime> _getEventsForDay(DateTime day) {
    if (_loggedDays.contains(DateTime.utc(day.year, day.month, day.day))) {
      return [day];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9), // Match home page background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
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
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Streak Calendar',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(30),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: const Color(0xFF5AA162),
              unselectedLabelColor: Colors.white,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 16,
              ),
              tabs: const [
                Tab(text: 'Personal'),
                Tab(text: 'Supervisor'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPersonalTab(),
          _buildSupervisorTab(),
        ],
      ),
       bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0, // Home
        onTap: (index) async {
          if (index == 0) {
            UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
            if (currentUser != null) {
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => HomePage(user: currentUser)),
                  (route) => false);
            }
          } else if (index == 1) {
            UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
            if (currentUser != null) {
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => ProgressPage(user: currentUser)),
                  (route) => false);
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

  Widget _buildPersonalTab() {
    bool hasLoggedToday = _loggedDays.contains(DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day));
    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF5AA162)))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // Enhanced streak display card
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: hasLoggedToday 
                              ? [const Color(0xFF5AA162), const Color(0xFF7BB77E)]
                              : [Colors.grey.shade400, Colors.grey.shade500],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Image.asset(
                            hasLoggedToday ? 'assets/Logged.png' : 'assets/Notlog.png',
                            width: 50,
                            height: 50,
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentStreak.toString(),
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5AA162),
                            ),
                          ),
                          const Text(
                            'day streak!',
                            style: TextStyle(
                              fontSize: 18,
                              color: Color(0xFF5AA162),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Enhanced calendar container
                Container(
                  padding: const EdgeInsets.all(20),
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
                  child: TableCalendar(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _focusedDay,
                    calendarFormat: CalendarFormat.month,
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5AA162),
                      ),
                      leftChevronIcon: Icon(Icons.chevron_left, color: Color(0xFF5AA162), size: 28),
                      rightChevronIcon: Icon(Icons.chevron_right, color: Color(0xFF5AA162), size: 28),
                      headerPadding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                        color: Colors.grey.shade600, 
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      weekendStyle: TextStyle(
                        color: Colors.grey.shade600, 
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    eventLoader: (day) {
                      return _loggedDays.contains(DateTime.utc(day.year, day.month, day.day)) ? [day] : [];
                    },
                    selectedDayPredicate: (day) {
                      return isSameDay(_focusedDay, day);
                    },
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _focusedDay = focusedDay;
                      });
                    },
                    onPageChanged: (focusedDay) {
                      setState(() {
                        _focusedDay = focusedDay;
                      });
                    },
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, date, _) {
                        final hasStreak = _loggedDays.contains(DateTime.utc(date.year, date.month, date.day));
                        return Container(
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: hasStreak 
                              ? const Color(0xFF5AA162)
                              : Colors.transparent,
                          ),
                          child: Center(
                            child: Text(
                              '${date.day}',
                              style: TextStyle(
                                color: hasStreak 
                                    ? Colors.white 
                                    : (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday
                                        ? Colors.grey[400]
                                        : Colors.black87),
                                fontWeight: hasStreak ? FontWeight.bold : FontWeight.w500,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        );
                      },
                      todayBuilder: (context, date, _) {
                        final hasStreak = _loggedDays.contains(DateTime.utc(date.year, date.month, date.day));
                        return Container(
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: hasStreak 
                              ? const Color(0xFF5AA162)
                              : Colors.transparent,
                            border: Border.all(
                              color: const Color(0xFF5AA162),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${date.day}',
                              style: TextStyle(
                                color: hasStreak 
                                    ? Colors.white 
                                    : const Color(0xFF5AA162),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        );
                      },
                      selectedBuilder: (context, date, _) {
                        final hasStreak = _loggedDays.contains(DateTime.utc(date.year, date.month, date.day));
                        return Container(
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: hasStreak 
                                ? [const Color(0xFF5AA162), const Color(0xFF7BB77E)]
                                : [const Color(0xFF5AA162).withOpacity(0.8), const Color(0xFF7BB77E).withOpacity(0.8)],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${date.day}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      weekendTextStyle: TextStyle(color: Colors.grey.shade400),
                      defaultTextStyle: const TextStyle(color: Colors.black87),
                      cellMargin: const EdgeInsets.all(3),
                      cellPadding: const EdgeInsets.all(0),
                      tableBorder: const TableBorder(),
                      rowDecoration: const BoxDecoration(),
                    ),
                  ),
                ),
              ],
            ),
          );
  }

  Widget _buildSupervisorTab() {
    if (_isSupervisionLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF5AA162)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              'Supervisor Connections',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Display existing supervisions
          ..._supervisions.map((supervision) => Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: _buildUserStreakCard(
              name: supervision.otherUserName,
              streak: supervision.streak,
              gender: supervision.otherUserGender,
              hasLoggedToday: supervision.hasLoggedToday,
              otherUserLoggedToday: supervision.otherUserLoggedToday,
              supervisionId: supervision.supervisionId,
            ),
          )),
          
          // Enhanced invite card
          _buildInviteCard(),
        ],
      ),
    );
  }

  Widget _buildUserStreakCard({
    required String name,
    required int streak,
    required String gender,
    required bool hasLoggedToday,
    required bool otherUserLoggedToday,
    String? supervisionId,
  }) {
    return Container(
      padding: const EdgeInsets.all(16), // Reduced from 20
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: hasLoggedToday 
          ? Border.all(color: const Color(0xFF5AA162).withOpacity(0.3), width: 2)
          : null,
      ),
      child: Row(
        children: [
          // Enhanced avatar with gradient background
          Container(
            width: 48, // Reduced from 56
            height: 48, // Reduced from 56
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF5AA162).withOpacity(0.8),
                  const Color(0xFF7BB77E),
                ],
              ),
              borderRadius: BorderRadius.circular(14), // Reduced from 16
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12), // Reduced from 14
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12), // Reduced from 14
                  child: Image.asset(
                    gender.toLowerCase() == 'male' ? 'assets/Male.png' : 'assets/Female.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 12), // Reduced from 16
          
          // User info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 16, // Reduced from 18
                    color: Colors.black87,
                  ),
                ),
                 // Status text removed as requested
              ],
            ),
          ),
          
          // Streak display and actions
          Row(
            children: [
              // Streak indicator
              Container(
                padding: const EdgeInsets.all(10), // Reduced from 12
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: hasLoggedToday 
                      ? [const Color(0xFF5AA162), const Color(0xFF7BB77E)]
                      : [Colors.grey.shade300, Colors.grey.shade400],
                  ),
                  borderRadius: BorderRadius.circular(14), // Reduced from 16
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      hasLoggedToday ? 'assets/Logged.png' : 'assets/Notlog.png',
                      width: 20, // Reduced from 24
                      height: 20, // Reduced from 24
                    ),
                    const SizedBox(width: 6), // Reduced from 8
                    Text(
                      '$streak',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18, // Reduced from 20
                      ),
                    ),
                  ],
                ),
              ),
              
              // Notification button - only show when appropriate
              if (((_currentUserLoggedToday && !otherUserLoggedToday) || 
                   (!_currentUserLoggedToday && !otherUserLoggedToday)) && 
                  supervisionId != null) ...[
                const SizedBox(width: 10), // Reduced from 12
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF5AA162),
                    borderRadius: BorderRadius.circular(10), // Reduced from 12
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5AA162).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _showCustomMessageDialog({
                        'supervisionId': supervisionId,
                        'name': name,
                        'gender': gender,
                      }),
                      borderRadius: BorderRadius.circular(10), // Reduced from 12
                      child: const Padding(
                        padding: EdgeInsets.all(10), // Reduced from 12
                        child: Icon(
                          Icons.notifications_outlined,
                          color: Colors.white,
                          size: 18, // Reduced from 20
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInviteCard() {
    return Container(
      padding: const EdgeInsets.all(16), // Reduced from 20
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF5AA162).withOpacity(0.1),
            const Color(0xFF7BB77E).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF5AA162).withOpacity(0.3), 
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
            if (currentUser != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => InviteSupervisorPage(currentUser: currentUser),
                ),
              ).then((_) {
                setState(() {
                  _isSupervisionLoading = true;
                });
                _fetchSupervisions();
              });
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              // Invite icon
              Container(
                width: 48, // Reduced from 56
                height: 48, // Reduced from 56
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF5AA162),
                      Color(0xFF7BB77E),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14), // Reduced from 16
                ),
                child: const Icon(
                  Icons.person_add_outlined,
                  color: Colors.white,
                  size: 24, // Reduced from 28
                ),
              ),
              
              const SizedBox(width: 12), // Reduced from 16
              
              // Invite text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invite Supervisor',
                      style: TextStyle(
                        fontSize: 16, // Reduced from 18
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5AA162),
                      ),
                    ),
                    const SizedBox(height: 3), // Reduced from 4
                    Text(
                      'Add someone to track your progress',
                      style: TextStyle(
                        fontSize: 12, // Reduced from 14
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Arrow icon
              Container(
                padding: const EdgeInsets.all(6), // Reduced from 8
                decoration: BoxDecoration(
                  color: const Color(0xFF5AA162).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10), // Reduced from 12
                ),
                child: const Icon(
                  Icons.arrow_forward_ios,
                  color: Color(0xFF5AA162),
                  size: 14, // Reduced from 16
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomMessageDialog(Map<String, dynamic> supervisor) {
    // Navigate to custom message page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomMessagePage(
          supervisor: supervisor,
          currentUserId: widget.user?.userID ?? '',
        ),
      ),
    );
  }

  Future<void> _sendCustomMessage(Map<String, dynamic> supervisor) async {
    try {
      final supervisionId = supervisor['supervisionId'];
      final message = supervisor['customMessage'] ?? '';
      
      // Get current user info
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null) return;
      
      // Get supervisor user ID from supervision
      final supervisionQuery = await FirebaseFirestore.instance
          .collection('Supervision')
          .where('SupervisionID', isEqualTo: supervisionId)
          .get();
      
      if (supervisionQuery.docs.isEmpty) return;
      
      final supervisionData = supervisionQuery.docs.first.data();
      final supervisorUserId = supervisionData['SupervisorID'];
      
      // Use Global Notification Manager for immediate delivery
      final globalNotificationManager = GlobalNotificationManager();
      await globalNotificationManager.sendRTDBNotification(
        receiverId: supervisorUserId,
        type: 'notification',
        data: {
          'title': 'Reminder from ${currentUser.firstName ?? 'Supervisor'}',
          'message': message.isNotEmpty ? message : "Don't forget to log your meals today! 🍽️",
          'senderId': currentUser.userID,
          'senderName': currentUser.firstName ?? 'Supervisor',
          'timestamp': DateTime.now().toIso8601String(),
          'type': 'log_food_reminder',
        },
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder sent successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Return to previous page
      Navigator.pop(context);
    } catch (e) {
      print('Error sending reminder: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending reminder: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}













