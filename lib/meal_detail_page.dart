import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/session_service.dart';
import 'package:caloriecare/log_food.dart';

class MealDetailPage extends StatefulWidget {
  final String mealType;
  final UserModel? user;
  final DateTime selectedDate;

  const MealDetailPage({
    Key? key,
    required this.mealType,
    required this.user,
    required this.selectedDate,
  }) : super(key: key);

  @override
  State<MealDetailPage> createState() => _MealDetailPageState();
}

class _MealDetailPageState extends State<MealDetailPage> with TickerProviderStateMixin {
  List<Map<String, dynamic>> foodItems = [];
  bool isLoading = true;
  int totalCalories = 0;
  double totalProtein = 0;
  double totalCarbs = 0;
  double totalFat = 0;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  String? currentLogID;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadMealData();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadMealData() async {
    try {
      UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
      if (currentUser == null || currentUser.userID.isEmpty) return;
      String userID = currentUser.userID;

      String selectedDateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
      
      // Debug information
      print('Loading meal data for:');
      print('UserID: $userID');
      print('SelectedDate: $selectedDateStr');
      print('MealType: ${widget.mealType}');

      // 获取该餐点的LogMeal记录
      QuerySnapshot logMealSnapshot = await FirebaseFirestore.instance
          .collection('LogMeal')
          .where('UserID', isEqualTo: userID)
          .where('LogDate', isEqualTo: selectedDateStr)
          .where('MealType', isEqualTo: widget.mealType)
          .get();

      print('Found ${logMealSnapshot.docs.length} LogMeal records');
      
      // Let's try a simpler query first
      QuerySnapshot simpleQuery = await FirebaseFirestore.instance
          .collection('LogMeal')
          .where('UserID', isEqualTo: userID)
          .get();
      
      print('Simple query (UserID only): ${simpleQuery.docs.length} records');
      for (var doc in simpleQuery.docs) {
        print('Simple query record: ${doc.data()}');
      }

      if (logMealSnapshot.docs.isEmpty) {
        // Let's check what records exist for this user and date
        QuerySnapshot allRecords = await FirebaseFirestore.instance
            .collection('LogMeal')
            .where('UserID', isEqualTo: userID)
            .where('LogDate', isEqualTo: selectedDateStr)
            .get();
        
        print('Total records for user on this date: ${allRecords.docs.length}');
        for (var doc in allRecords.docs) {
          print('Record: ${doc.data()}');
        }
        
        setState(() {
          isLoading = false;
          foodItems = [];
          currentLogID = null;
        });
        return;
      }

      String logID = logMealSnapshot.docs.first['LogID'];
      currentLogID = logID;
      totalCalories = logMealSnapshot.docs.first['TotalCalories'] ?? 0;
      totalProtein = (logMealSnapshot.docs.first['TotalProtein'] ?? 0).toDouble();
      totalCarbs = (logMealSnapshot.docs.first['TotalCarbs'] ?? 0).toDouble();
      totalFat = (logMealSnapshot.docs.first['TotalFat'] ?? 0).toDouble();

      print('LogID: $logID');
      print('Total Calories: $totalCalories');

      // 获取该餐点的所有食物
      QuerySnapshot logMealListSnapshot = await FirebaseFirestore.instance
          .collection('LogMealList')
          .where('LogID', isEqualTo: logID)
          .get();

      print('Found ${logMealListSnapshot.docs.length} LogMealList records for LogID: $logID');

      List<Map<String, dynamic>> foods = [];
      for (DocumentSnapshot doc in logMealListSnapshot.docs) {
        print('LogMealList record: ${doc.data()}');
        String foodID = doc['FoodID'];
        
        // 获取食物详细信息 - 使用where查询而不是doc查询
        QuerySnapshot foodQuery = await FirebaseFirestore.instance
            .collection('Food')
            .where('FoodID', isEqualTo: foodID)
            .get();

        if (foodQuery.docs.isNotEmpty) {
          DocumentSnapshot foodDoc = foodQuery.docs.first;
          Map<String, dynamic> foodData = foodDoc.data() as Map<String, dynamic>;
          print('Food data: ${foodData}');
          
          // 计算分量
          double originalCalories = (foodData['Calories'] ?? 0).toDouble();
          double loggedCalories = (doc['SubCalories'] ?? 0).toDouble();
          double quantity = 0;
          if (originalCalories > 0) {
            quantity = (loggedCalories / originalCalories) * 100; // 假设原始单位是100g
          }
          
          foods.add({
            'foodName': foodData['FoodName'] ?? 'Unknown Food',
            'calories': doc['SubCalories'] ?? 0,
            'protein': (doc['SubProtein'] ?? 0).toDouble(),
            'carbs': (doc['SubCarbs'] ?? 0).toDouble(),
            'fat': (doc['SubFat'] ?? 0).toDouble(),
            'unit': foodData['Unit'] ?? '100g',
            'quantity': quantity,
            'logMealListID': doc.id, // 保存LogMealList的文档ID用于编辑
            'foodID': foodID,
            'originalCalories': originalCalories,
          });
        } else {
          print('Food document not found for FoodID: $foodID');
          // 即使Food表中没有记录，也显示LogMealList中的数据
          foods.add({
            'foodName': 'Food ID: $foodID', // 使用FoodID作为食物名称
            'calories': doc['SubCalories'] ?? 0,
            'protein': (doc['SubProtein'] ?? 0).toDouble(),
            'carbs': (doc['SubCarbs'] ?? 0).toDouble(),
            'fat': (doc['SubFat'] ?? 0).toDouble(),
            'unit': '100g',
            'quantity': 100, // 默认分量
            'logMealListID': doc.id,
            'foodID': foodID,
            'originalCalories': 0,
          });
        }
      }

      print('Final foods list: $foods');

      setState(() {
        foodItems = foods;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading meal details: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  void _navigateToLogFood() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LogFoodPage(
          mealType: widget.mealType,
          user: widget.user,
          selectedDate: widget.selectedDate,
        ),
      ),
    );
    
    // 如果从LogFood页面返回，刷新数据
    if (result == true) {
      _loadMealData();
    }
  }

  void _showEditQuantityDialog(Map<String, dynamic> food) {
    TextEditingController quantityController = TextEditingController(
      text: food['quantity'].toStringAsFixed(1),
    );
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getMealColor(widget.mealType).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.edit,
                  color: _getMealColor(widget.mealType),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Edit ${food['foodName']}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAF9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getMealColor(widget.mealType).withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [


                          Text(
                            'Current quantity: ',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF7F8C8D),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              '${food['quantity'].toStringAsFixed(1)}g',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _getMealColor(widget.mealType),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),


                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF2C3E50),
                ),
                decoration: InputDecoration(
                  labelText: 'New quantity (g)',
                  labelStyle: const TextStyle(
                    color: Color(0xFF7F8C8D),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _getMealColor(widget.mealType).withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _getMealColor(widget.mealType),
                      width: 2,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.edit_note,
                    color: _getMealColor(widget.mealType),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF7F8C8D),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 16),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                double newQuantity = double.tryParse(quantityController.text) ?? 0;
                if (newQuantity <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please enter a valid quantity'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                  return;
                }
                
                Navigator.of(context).pop();
                await _updateFoodQuantity(food, newQuantity);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _getMealColor(widget.mealType),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'Update',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(Map<String, dynamic> food) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
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
                  Icons.delete_forever,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Delete Food',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAF9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.restaurant,
                      color: _getMealColor(widget.mealType),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Are you sure you want to delete "${food['foodName']}"?',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'This action cannot be undone.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF7F8C8D),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 16),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteFood(food);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteFood(Map<String, dynamic> food) async {
    try {
      // 删除LogMealList记录
      await FirebaseFirestore.instance
          .collection('LogMealList')
          .doc(food['logMealListID'])
          .delete();

      // 重新计算并更新LogMeal的总营养值
      if (currentLogID != null) {
        QuerySnapshot logMealListSnapshot = await FirebaseFirestore.instance
            .collection('LogMealList')
            .where('LogID', isEqualTo: currentLogID)
            .get();

        double totalCal = 0, totalProtein = 0, totalCarbs = 0, totalFat = 0;
        for (var doc in logMealListSnapshot.docs) {
          totalCal += (doc['SubCalories'] ?? 0).toDouble();
          totalProtein += (doc['SubProtein'] ?? 0).toDouble();
          totalCarbs += (doc['SubCarbs'] ?? 0).toDouble();
          totalFat += (doc['SubFat'] ?? 0).toDouble();
        }

        // 更新LogMeal记录
        QuerySnapshot logMealSnapshot = await FirebaseFirestore.instance
            .collection('LogMeal')
            .where('LogID', isEqualTo: currentLogID)
            .get();

        if (logMealSnapshot.docs.isNotEmpty) {
          await logMealSnapshot.docs.first.reference.update({
            'TotalCalories': totalCal.round(),
            'TotalProtein': double.parse(totalProtein.toStringAsFixed(2)),
            'TotalCarbs': double.parse(totalCarbs.toStringAsFixed(2)),
            'TotalFat': double.parse(totalFat.toStringAsFixed(2)),
          });
        }

        // 如果这是最后一个食物，删除整个LogMeal记录
        if (logMealListSnapshot.docs.isEmpty) {
          await logMealSnapshot.docs.first.reference.delete();
          setState(() {
            currentLogID = null;
          });
        }
      }

      // 刷新数据
      _loadMealData();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              const Text('Food deleted successfully!'),
            ],
          ),
          backgroundColor: const Color(0xFF5AA162),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Text('Error deleting food: $e'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _updateFoodQuantity(Map<String, dynamic> food, double newQuantity) async {
    try {
      // 获取原始食物的营养值
      QuerySnapshot foodQuery = await FirebaseFirestore.instance
          .collection('Food')
          .where('FoodID', isEqualTo: food['foodID'])
          .get();

      if (foodQuery.docs.isEmpty) {
        throw Exception('Food not found');
      }

      DocumentSnapshot foodDoc = foodQuery.docs.first;
      Map<String, dynamic> foodData = foodDoc.data() as Map<String, dynamic>;
      
      // 计算新的营养值
      double originalCalories = (foodData['Calories'] ?? 0).toDouble();
      double originalProtein = (foodData['Protein'] ?? 0).toDouble();
      double originalCarbs = (foodData['Carbohydrates'] ?? 0).toDouble();
      double originalFat = (foodData['Fat'] ?? 0).toDouble();
      
      double ratio = newQuantity / 100; // 假设原始单位是100g
      double newCalories = originalCalories * ratio;
      double newProtein = originalProtein * ratio;
      double newCarbs = originalCarbs * ratio;
      double newFat = originalFat * ratio;

      // 更新LogMealList记录
      await FirebaseFirestore.instance
          .collection('LogMealList')
          .doc(food['logMealListID'])
          .update({
        'SubCalories': newCalories.round(),
        'SubProtein': double.parse(newProtein.toStringAsFixed(2)),
        'SubCarbs': double.parse(newCarbs.toStringAsFixed(2)),
        'SubFat': double.parse(newFat.toStringAsFixed(2)),
      });

      // 重新计算并更新LogMeal的总营养值
      if (currentLogID != null) {
        QuerySnapshot logMealListSnapshot = await FirebaseFirestore.instance
            .collection('LogMealList')
            .where('LogID', isEqualTo: currentLogID)
            .get();

        double totalCal = 0, totalProtein = 0, totalCarbs = 0, totalFat = 0;
        for (var doc in logMealListSnapshot.docs) {
          totalCal += (doc['SubCalories'] ?? 0).toDouble();
          totalProtein += (doc['SubProtein'] ?? 0).toDouble();
          totalCarbs += (doc['SubCarbs'] ?? 0).toDouble();
          totalFat += (doc['SubFat'] ?? 0).toDouble();
        }

        // 更新LogMeal记录
        QuerySnapshot logMealSnapshot = await FirebaseFirestore.instance
            .collection('LogMeal')
            .where('LogID', isEqualTo: currentLogID)
            .get();

        if (logMealSnapshot.docs.isNotEmpty) {
          await logMealSnapshot.docs.first.reference.update({
            'TotalCalories': totalCal.round(),
            'TotalProtein': double.parse(totalProtein.toStringAsFixed(2)),
            'TotalCarbs': double.parse(totalCarbs.toStringAsFixed(2)),
            'TotalFat': double.parse(totalFat.toStringAsFixed(2)),
          });
        }
      }

      // 刷新数据
      _loadMealData();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              const Text('Food quantity updated successfully!'),
            ],
          ),
          backgroundColor: const Color(0xFF5AA162),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Text('Error updating food quantity: $e'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Text(
                  widget.mealType,
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                centerTitle: true,
              ),
              body: isLoading
                  ? Center(child: CircularProgressIndicator())
                  : foodItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.restaurant_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No foods logged for ${widget.mealType}',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                DateFormat('EEEE, MMMM d').format(widget.selectedDate),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                              SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: _navigateToLogFood,
                                icon: Icon(Icons.add),
                                label: Text('Add Food to ${widget.mealType}'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _getMealColor(widget.mealType),
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            // 营养总览卡片
                            Container(
                              margin: EdgeInsets.all(16),
                              padding: EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _getMealColor(widget.mealType).withOpacity(0.1),
                                    _getMealColor(widget.mealType).withOpacity(0.05),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _getMealColor(widget.mealType).withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Total Calories',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      Text(
                                        '$totalCalories kcal',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: _getMealColor(widget.mealType),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildNutrientCard('Protein', '${totalProtein.toStringAsFixed(1)}g', Colors.red),
                                      _buildNutrientCard('Carbs', '${totalCarbs.toStringAsFixed(1)}g', Colors.orange),
                                      _buildNutrientCard('Fat', '${totalFat.toStringAsFixed(1)}g', Colors.blue),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // 食物列表
                            Expanded(
                              child: ListView.builder(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                itemCount: foodItems.length,
                                itemBuilder: (context, index) {
                                  final food = foodItems[index];
                                  return Container(
                                    margin: EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withOpacity(0.1),
                                          spreadRadius: 1,
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.fromLTRB(16, 12, 8, 12),
                                      leading: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: _getMealColor(widget.mealType).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Icon(
                                          Icons.restaurant,
                                          color: _getMealColor(widget.mealType),
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        food['foodName'],
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  '${food['calories']} kcal',
                                                  style: TextStyle(
                                                    color: _getMealColor(widget.mealType),
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 13,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  '(${food['quantity'].toStringAsFixed(1)}g)',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 11,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  'P: ${food['protein'].toStringAsFixed(1)}g',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  'C: ${food['carbs'].toStringAsFixed(1)}g',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  'F: ${food['fat'].toStringAsFixed(1)}g',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            child: IconButton(
                                              icon: Icon(
                                                Icons.edit,
                                                color: _getMealColor(widget.mealType),
                                                size: 16,
                                              ),
                                              onPressed: () => _showEditQuantityDialog(food),
                                              padding: EdgeInsets.zero,
                                              constraints: BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          Container(
                                            width: 32,
                                            height: 32,
                                            child: IconButton(
                                              icon: Icon(
                                                Icons.delete,
                                                color: Colors.red,
                                                size: 16,
                                              ),
                                              onPressed: () => _showDeleteConfirmationDialog(food),
                                              padding: EdgeInsets.zero,
                                              constraints: BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNutrientCard(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              value.split('g')[0],
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Color _getMealColor(String meal) {
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
} 


