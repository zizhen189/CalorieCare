import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/recognite_food.dart';
import 'package:caloriecare/session_service.dart';
import 'package:caloriecare/homepage.dart';
import 'streak_service.dart';
import 'streak_page.dart';
import 'loading_utils.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LogFoodPage extends StatefulWidget {
  final String mealType;
  final UserModel? user;
  final DateTime? selectedDate;
  
  const LogFoodPage({
    Key? key, 
    required this.mealType, 
    this.user,
    this.selectedDate,
  }) : super(key: key);

  @override
  State<LogFoodPage> createState() => _LogFoodPageState();
}

class _LogFoodPageState extends State<LogFoodPage> with TickerProviderStateMixin {
  TextEditingController _searchController = TextEditingController();
  List<DocumentSnapshot> _foods = [];
  bool _isLoading = false;
  bool _isAiLoading = false;
  bool _showAiButton = false;
  String _lastSearchQuery = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  // Gemini API
  final String _geminiApiKey = dotenv.env['GEMINI_API_KEY']!;
  final String _geminiApiUrlBase = dotenv.env['GEMINI_API_URL']!;

  // Color scheme
  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color lightGreen = Color(0xFF81C784);
  static const Color darkGreen = Color(0xFF388E3C);
  static const Color backgroundColor = Color(0xFFF8F9FA);
  static const Color cardColor = Colors.white;
  static const Color textPrimary = Color(0xFF2E2E2E);
  static const Color textSecondary = Color(0xFF757575);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
    
    _fetchInitialFoods();
    _searchController.addListener(_onSearchChanged);
    _animationController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _fetchInitialFoods() async {
    setState(() => _isLoading = true);
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('Food')
          .limit(10)
          .get();
      setState(() {
        _foods = snapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Failed to load foods');
    }
  }

  void _onSearchChanged() async {
    String query = _searchController.text.trim();
    if (query.isEmpty) {
      _fetchInitialFoods();
      setState(() {
        _showAiButton = false;
        _lastSearchQuery = '';
      });
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      // Use multiple efficient Firestore queries
      List<DocumentSnapshot> results = await _performEfficientSearch(query);
      
      setState(() {
        _foods = results;
        _isLoading = false;
        // 如果没有找到结果，显示AI按钮
        _showAiButton = results.isEmpty && query.isNotEmpty;
        _lastSearchQuery = query;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Search failed');
    }
  }

  Future<List<DocumentSnapshot>> _performEfficientSearch(String query) async {
    final String lowerQuery = query.toLowerCase();
    final String upperQuery = query.toUpperCase();
    final String capitalizedQuery = query.substring(0, 1).toUpperCase() + 
        (query.length > 1 ? query.substring(1).toLowerCase() : '');
    
    // Set to store unique documents (avoid duplicates)
    final Map<String, DocumentSnapshot> uniqueResults = {};
    
    // 1. Exact match search (case-sensitive)
    final exactMatch = await FirebaseFirestore.instance
        .collection('Food')
        .where('FoodName', isEqualTo: query)
        .limit(5)
        .get();
    
    for (var doc in exactMatch.docs) {
      uniqueResults[doc.id] = doc;
    }
    
    // 2. Starts with search (case variations)
    final searchVariations = [query, lowerQuery, upperQuery, capitalizedQuery];
    
    for (String searchTerm in searchVariations) {
      final startsWithQuery = await FirebaseFirestore.instance
          .collection('Food')
          .where('FoodName', isGreaterThanOrEqualTo: searchTerm)
          .where('FoodName', isLessThanOrEqualTo: '$searchTerm\uf8ff')
          .limit(10)
          .get();
      
      for (var doc in startsWithQuery.docs) {
        uniqueResults[doc.id] = doc;
      }
    }
    
    // 3. If we have few results, do a broader search with array-contains
    if (uniqueResults.length < 5) {
      // Create search keywords for array-contains queries
      final keywords = _generateSearchKeywords(query);
      
      for (String keyword in keywords.take(3)) { // Limit to 3 keywords
        try {
          final keywordQuery = await FirebaseFirestore.instance
              .collection('Food')
              .where('SearchKeywords', arrayContains: keyword.toLowerCase())
              .limit(8)
              .get();
          
          for (var doc in keywordQuery.docs) {
            uniqueResults[doc.id] = doc;
          }
        } catch (e) {
          // SearchKeywords field might not exist, continue with other methods
          print('SearchKeywords field not found, skipping array-contains search');
        }
      }
    }
    
    // 4. If still few results, fall back to limited client-side filtering
    if (uniqueResults.length < 3) {
      final fallbackQuery = await FirebaseFirestore.instance
          .collection('Food')
          .limit(50) // Reduced from 100
          .get();
      
      final filtered = fallbackQuery.docs.where((doc) {
        String name = (doc['FoodName'] ?? '').toString().toLowerCase();
        return name.contains(lowerQuery);
      }).take(10);
      
      for (var doc in filtered) {
        uniqueResults[doc.id] = doc;
      }
    }
    
    // Sort results by relevance (exact matches first, then starts-with, then contains)
    final sortedResults = uniqueResults.values.toList();
    sortedResults.sort((a, b) {
      String nameA = (a['FoodName'] ?? '').toString().toLowerCase();
      String nameB = (b['FoodName'] ?? '').toString().toLowerCase();
      
      // Exact match gets highest priority
      if (nameA == lowerQuery && nameB != lowerQuery) return -1;
      if (nameB == lowerQuery && nameA != lowerQuery) return 1;
      
      // Starts with gets second priority
      bool aStartsWith = nameA.startsWith(lowerQuery);
      bool bStartsWith = nameB.startsWith(lowerQuery);
      if (aStartsWith && !bStartsWith) return -1;
      if (bStartsWith && !aStartsWith) return 1;
      
      // Alphabetical order for same priority
      return nameA.compareTo(nameB);
    });
    
    return sortedResults.take(10).toList();
  }

  List<String> _generateSearchKeywords(String query) {
    final keywords = <String>[];
    final words = query.toLowerCase().split(' ');
    
    // Add individual words
    keywords.addAll(words);
    
    // Add partial words (for partial matching)
    for (String word in words) {
      if (word.length > 2) {
        for (int i = 2; i <= word.length; i++) {
          keywords.add(word.substring(0, i));
        }
      }
    }
    
    return keywords.toSet().toList(); // Remove duplicates
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // Optional: Method to update existing Food documents with search keywords
  Future<void> _updateFoodWithSearchKeywords() async {
    // This is a one-time migration function - run once to enhance search
    final foods = await FirebaseFirestore.instance.collection('Food').get();
    
    for (var doc in foods.docs) {
      final foodName = doc['FoodName']?.toString() ?? '';
      final keywords = _generateSearchKeywords(foodName);
      
      await doc.reference.update({
        'SearchKeywords': keywords,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            children: [
              _buildSearchSection(),
              Expanded(child: _buildFoodList()),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: primaryGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.arrow_back_ios_new, color: primaryGreen, size: 18),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.mealType,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          Text(
            'Add food to your meal',
            style: TextStyle(
              fontSize: 14,
              color: textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          child: Material(
            color: primaryGreen,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _navigateToCamera,
              child: Container(
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 24),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchSection() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 16, color: textPrimary),
        decoration: InputDecoration(
          hintText: 'Search for food...',
          hintStyle: TextStyle(color: textSecondary, fontSize: 16),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: Icon(Icons.search_rounded, color: primaryGreen, size: 24),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    _fetchInitialFoods();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildFoodList() {
    if (_isLoading) {
      return _buildLoadingState();
    }
    
    if (_foods.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _foods.length,
      itemBuilder: (context, index) {
        final food = _foods[index];
        return _buildFoodCard(food, index);
      },
    );
  }

  Widget _buildFoodCard(DocumentSnapshot food, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showFoodModal(food),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Food icon
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primaryGreen.withOpacity(0.8),
                        lightGreen.withOpacity(0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                // Food info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        food['FoodName'] ?? 'Unknown Food',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Fixed the overflow issue here
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _buildInfoChip(
                            '${(food['Calories'] ?? 0).toStringAsFixed(1)} kcal',
                            Icons.local_fire_department_rounded,
                            Colors.orange,
                          ),
                          _buildInfoChip(
                            'per ${food['Unit'] ?? 100}g',
                            Icons.scale_rounded,
                            primaryGreen,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Add button
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: primaryGreen,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: primaryGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(primaryGreen),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Loading delicious foods...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No foods found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with different keywords\nor use the camera to scan food',
              style: TextStyle(
                fontSize: 16,
                color: textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // AI按钮 - 只在搜索有结果时显示
            if (_showAiButton && _lastSearchQuery.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.blue.shade600, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Not found in database',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Get nutrition info for "$_lastSearchQuery" using AI',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isAiLoading ? null : () => _getFoodNutritionFromAI(_lastSearchQuery ?? ''),
                      icon: _isAiLoading 
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(Icons.auto_awesome),
                      label: Text(_isAiLoading ? 'Getting Info...' : 'Get AI Nutrition'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
            ],
            ElevatedButton.icon(
              onPressed: _navigateToCamera,
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Scan Food'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFoodModal(DocumentSnapshot food) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildFoodModal(food),
    );
  }

  Widget _buildFoodModal(DocumentSnapshot food) {
    // Extract numeric value from Unit field (e.g., "per 100g" -> 100)
    String unitString = (food['Unit'] ?? '100g').toString();
    int dbQty = _extractNumericFromUnit(unitString);
    
    TextEditingController qtyController = TextEditingController(text: dbQty.toString());
    int quantity = dbQty;

    double cal = (food['Calories'] ?? 0).toDouble();
    double carb = (food['Carbohydrates'] ?? 0).toDouble();
    double protein = (food['Protein'] ?? 0).toDouble();
    double fat = (food['Fat'] ?? 0).toDouble();

    return StatefulBuilder(
      builder: (context, setModalState) {
        double ratio = (quantity > 0) ? quantity / dbQty : 0;
        double showCal = cal * ratio;
        double showCarb = carb * ratio;
        double showProtein = protein * ratio;
        double showFat = fat * ratio;

        return Container(
          decoration: const BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Food header
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [primaryGreen, lightGreen],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            food['FoodName'] ?? 'Unknown Food',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            unitString,
                            style: TextStyle(
                              fontSize: 13,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Nutrition grid
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildNutrientCard('Calories', '${showCal.toStringAsFixed(1)}', 'kcal', Colors.orange)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildNutrientCard('Protein', '${showProtein.toStringAsFixed(1)}', 'g', Colors.blue)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildNutrientCard('Carbs', '${showCarb.toStringAsFixed(1)}', 'g', Colors.green)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildNutrientCard('Fat', '${showFat.toStringAsFixed(1)}', 'g', Colors.red)),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Quantity input
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.scale_rounded, color: primaryGreen, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Quantity (g):',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: qtyController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: primaryGreen.withOpacity(0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: primaryGreen, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onChanged: (value) {
                            setModalState(() {
                              quantity = int.tryParse(value) ?? 0;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Add button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      int finalQty = int.tryParse(qtyController.text) ?? 0;
                      if (finalQty < 1) {
                        _showErrorSnackBar('Please enter a valid quantity!');
                        return;
                      }

                      double ratio = (finalQty > 0) ? finalQty / dbQty : 0;
                      double finalCal = cal * ratio;
                      double finalCarb = carb * ratio;
                      double finalProtein = protein * ratio;
                      double finalFat = fat * ratio;

                      Navigator.pop(context);
                      await _saveFoodToFirebase(
                        food,
                        finalQty,
                        finalCal,
                        finalProtein,
                        finalCarb,
                        finalFat,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Add to Meal',
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
        );
      },
    );
  }

  Widget _buildNutrientCard(String label, String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(
            _getNutrientIcon(label),
            color: color,
            size: 20,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 10,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getNutrientIcon(String nutrient) {
    switch (nutrient.toLowerCase()) {
      case 'calories':
        return Icons.local_fire_department_rounded;
      case 'protein':
        return Icons.fitness_center_rounded;
      case 'carbs':
        return Icons.grain_rounded;
      case 'fat':
        return Icons.opacity_rounded;
      default:
        return Icons.restaurant_rounded;
    }
  }

  void _navigateToCamera() async {
    String userId = await _getUserID();
    if (userId.isEmpty) {
      _showErrorSnackBar('User not found. Please login again.');
      return;
    }
    
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecogniteFoodPage(
          mealType: widget.mealType,
          userId: userId,
          user: currentUser,
          selectedDate: widget.selectedDate,
        ),
      ),
    );
    
    if (result == true) {
      _fetchInitialFoods();
    }
  }

  // AI功能：获取食物营养信息
  Future<void> _getFoodNutritionFromAI(String foodName) async {
    setState(() {
      _isAiLoading = true;
    });

    try {
      final prompt = '''
请为食物 '$foodName'，基于一份标准份量（约100克），提供其营养信息。
请以JSON格式返回，包含以下字段：
- calories: 卡路里 (kcal)
- protein: 蛋白质 (g)
- carbs: 碳水化合物 (g)
- fat: 脂肪 (g)
- unit: 100 (固定值)

示例格式：
{
  "calories": 250,
  "protein": 12.5,
  "carbs": 30.0,
  "fat": 8.5,
  "unit": 100
}
''';

      final requestBody = {
        'contents': [
          {
            'parts': [
              {
                'text': prompt,
              },
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.3,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 1024,
        },
        'safetySettings': [
          {
            'category': 'HARM_CATEGORY_HARASSMENT',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
          },
          {
            'category': 'HARM_CATEGORY_HATE_SPEECH',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
          },
          {
            'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
          },
          {
            'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE'
          }
        ]
      };

      final fullApiUrl = '$_geminiApiUrlBase?key=$_geminiApiKey';
      
      final response = await http.post(
        Uri.parse(fullApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        String generatedContent = '';
        if (responseData['candidates'] != null &&
            responseData['candidates'].isNotEmpty &&
            responseData['candidates'][0]['content'] != null &&
            responseData['candidates'][0]['content']['parts'] != null &&
            responseData['candidates'][0]['content']['parts'].isNotEmpty) {
          generatedContent = responseData['candidates'][0]['content']['parts'][0]['text'];
        }
        
        print('AI Response: $generatedContent');
        
        // 解析AI返回的JSON数据
        final nutritionData = _parseNutritionData(generatedContent);
        if (nutritionData != null) {
          _showNutritionConfirmationDialog(foodName, nutritionData);
        } else {
          throw Exception('Failed to parse AI response');
        }
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error getting nutrition from AI: $e');
      String errorMessage = 'Failed to get nutrition information';
      
      if (e.toString().contains('timeout')) {
        errorMessage = 'Request timed out, please check your network connection.';
      } else if (e.toString().contains('API Error: 429')) {
        errorMessage = 'API requests are too frequent. Please try again later.';
      } else if (e.toString().contains('API Error: 401')) {
        errorMessage = 'API key invalid, please contact the developer';
      } else if (e.toString().contains('API Error: 403')) {
        errorMessage = 'API access denied, please contact the developer.';
      } else if (e.toString().contains('network')) {
        errorMessage = 'Network connection failed. Please check your network settings.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        _isAiLoading = false;
      });
    }
  }

  // 解析AI返回的营养数据
  Map<String, dynamic>? _parseNutritionData(String aiResponse) {
    try {
      // 尝试提取JSON部分
      final jsonMatch = RegExp(r'\{[^{}]*"calories"[^{}]*\}').firstMatch(aiResponse);
      if (jsonMatch != null) {
        final jsonString = jsonMatch.group(0);
        if (jsonString != null) {
          final data = jsonDecode(jsonString);
          
          return {
            'calories': data['calories']?.toDouble() ?? 0.0,
            'protein': data['protein']?.toDouble() ?? 0.0,
            'carbs': data['carbs']?.toDouble() ?? 0.0,
            'fat': data['fat']?.toDouble() ?? 0.0,
            'unit': data['unit']?.toInt() ?? 100,
          };
        }
      }
      return null;
    } catch (e) {
      print('Error parsing nutrition data: $e');
      return null;
    }
  }

  // 显示营养信息确认对话框
  void _showNutritionConfirmationDialog(String foodName, Map<String, dynamic> nutritionData) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.restaurant, color: primaryGreen),
              SizedBox(width: 8),
              Text('Confirm Nutrition Info'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Food: $foodName',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 16),
              Text('Nutrition per 100g:'),
              SizedBox(height: 8),
              _buildNutritionRow('Calories', '${nutritionData['calories'].round()} kcal'),
              _buildNutritionRow('Protein', '${nutritionData['protein'].toStringAsFixed(1)}g'),
              _buildNutritionRow('Carbs', '${nutritionData['carbs'].toStringAsFixed(1)}g'),
              _buildNutritionRow('Fat', '${nutritionData['fat'].toStringAsFixed(1)}g'),
              SizedBox(height: 16),
              Text(
                'Is this information accurate?',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _addFoodToDatabase(foodName, nutritionData);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
              child: Text('Confirm & Add'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNutritionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // 添加食物到数据库
  Future<void> _addFoodToDatabase(String foodName, Map<String, dynamic> nutritionData) async {
    try {
      // 生成新的FoodID
      final foodQuery = await FirebaseFirestore.instance
          .collection('Food')
          .orderBy('FoodID', descending: true)
          .limit(1)
          .get();
      
      String newFoodId;
      if (foodQuery.docs.isEmpty) {
        newFoodId = 'F00001';
      } else {
        final lastId = foodQuery.docs.first['FoodID'] as String;
        final lastNumber = int.parse(lastId.substring(1));
        newFoodId = 'F${(lastNumber + 1).toString().padLeft(5, '0')}';
      }

      // 添加食物到数据库
      await FirebaseFirestore.instance.collection('Food').add({
        'FoodID': newFoodId,
        'FoodName': foodName,
        'Calories': nutritionData['calories'],
        'Protein': nutritionData['protein'],
        'Carbohydrates': nutritionData['carbs'],
        'Fat': nutritionData['fat'],
        'Unit': nutritionData['unit'],
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Food "$foodName" added to database successfully!'),
          backgroundColor: primaryGreen,
          duration: Duration(seconds: 3),
        ),
      );

      // 刷新搜索结果
      _onSearchChanged();
    } catch (e) {
      print('Error adding food to database: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add food to database'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Keep all existing methods for Firebase operations
  Future<String> _getUserID() async {
    UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
    return currentUser?.userID ?? '';
  }

  Future<String> _generateLogID() async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('LogMeal')
        .orderBy('LogID', descending: true)
        .limit(1)
        .get();
    
    if (snapshot.docs.isEmpty) {
      return 'L00001';
    }
    
    String lastID = snapshot.docs.first['LogID'];
    int number = int.parse(lastID.substring(1)) + 1;
    return 'L${number.toString().padLeft(5, '0')}';
  }

  Future<void> _saveFoodToFirebase(
    DocumentSnapshot food,
    int quantity,
    double calories,
    double protein,
    double carbs,
    double fat,
  ) async {
    try {
      String userID = await _getUserID();
      if (userID.isEmpty) {
        _showErrorSnackBar('User not found. Please login again.');
        return;
      }

      DateTime targetDate = widget.selectedDate ?? DateTime.now();
      String targetDateStr = "${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
      
      // Check streak conditions
      DateTime today = DateTime.now();
      String todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      bool isLoggingForToday = targetDateStr == todayStr;
      
      QuerySnapshot todayLogs = await FirebaseFirestore.instance
          .collection('LogMeal')
          .where('UserID', isEqualTo: userID)
          .where('LogDate', isEqualTo: todayStr)
          .get();
      bool isFirstLogOfToday = todayLogs.docs.isEmpty;
      
      DocumentSnapshot? userDoc = await FirebaseFirestore.instance
          .collection('User')
          .where('UserID', isEqualTo: userID)
          .get()
          .then((snapshot) => snapshot.docs.isNotEmpty ? snapshot.docs.first : null);
      
      String? lastStreakUpdate = userDoc?.data() != null 
          ? (userDoc!.data() as Map<String, dynamic>)['LastStreakUpdate'] as String?
          : null;
      bool streakAlreadyUpdatedToday = lastStreakUpdate == todayStr;
      
      bool shouldUpdateStreak = isFirstLogOfToday && !streakAlreadyUpdatedToday && isLoggingForToday;

      await LoadingUtils.showLoadingWhile(
        context,
        () async {
          QuerySnapshot existingMeal = await FirebaseFirestore.instance
              .collection('LogMeal')
              .where('UserID', isEqualTo: userID)
              .where('LogDate', isEqualTo: targetDateStr)
              .where('MealType', isEqualTo: widget.mealType)
              .get();

          String logID;
          if (existingMeal.docs.isNotEmpty) {
            DocumentSnapshot existingDoc = existingMeal.docs.first;
            logID = existingDoc['LogID'];
            
            double existingCalories = (existingDoc['TotalCalories'] ?? 0).toDouble();
            double existingProtein = (existingDoc['TotalProtein'] ?? 0).toDouble();
            double existingCarbs = (existingDoc['TotalCarbs'] ?? 0).toDouble();
            double existingFat = (existingDoc['TotalFat'] ?? 0).toDouble();

            await existingDoc.reference.update({
              'TotalCalories': (existingCalories + calories).round(),
              'TotalProtein': double.parse((existingProtein + protein).toStringAsFixed(2)),
              'TotalCarbs': double.parse((existingCarbs + carbs).toStringAsFixed(2)),
              'TotalFat': double.parse((existingFat + fat).toStringAsFixed(2)),
            });
          } else {
            logID = await _generateLogID();
            await FirebaseFirestore.instance.collection('LogMeal').add({
              'LogID': logID,
              'UserID': userID,
              'LogDate': targetDateStr,
              'MealType': widget.mealType,
              'TotalCalories': calories.round(),
              'TotalProtein': double.parse(protein.toStringAsFixed(2)),
              'TotalCarbs': double.parse(carbs.toStringAsFixed(2)),
              'TotalFat': double.parse(fat.toStringAsFixed(2)),
            });
          }

          await FirebaseFirestore.instance.collection('LogMealList').add({
            'LogID': logID,
            'FoodID': food['FoodID'],
            'SubCalories': calories.round(),
            'SubProtein': double.parse(protein.toStringAsFixed(2)),
            'SubCarbs': double.parse(carbs.toStringAsFixed(2)),
            'SubFat': double.parse(fat.toStringAsFixed(2)),
          });
        },
        message: 'Adding food to your meal...',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              const Text('Food added successfully!'),
            ],
          ),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

      if (context.mounted) {
        UserModel? currentUser = widget.user ?? await SessionService.getUserSession();
        
        if (shouldUpdateStreak) {
          Map<String, dynamic> streakData = await StreakService().updateUserStreak(userID);
          
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => StreakPage(
                streakDays: streakData['streakDays'],
                isNewDay: streakData['isNewDay'],
                user: currentUser,
                selectedDate: widget.selectedDate,
              ),
            ),
            (route) => false,
          );
        } else {
          Navigator.of(context).pop(true); // 返回true表示成功添加食物
        }
      }
    } catch (e) {
      _showErrorSnackBar('Error saving food: $e');
    }
  }

  // Helper method to extract numeric value from unit string
  int _extractNumericFromUnit(String unitString) {
    // Extract numbers from strings like "per 100g", "100g", "per 50ml", etc.
    final RegExp numberRegex = RegExp(r'(\d+)');
    final match = numberRegex.firstMatch(unitString);
    return match != null ? int.parse(match.group(1)!) : 100;
  }
}















































