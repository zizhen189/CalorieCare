import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/recognite_food.dart';
import 'package:caloriecare/session_service.dart';
import 'package:caloriecare/homepage.dart';
import 'streak_service.dart';
import 'streak_page.dart';
import 'loading_utils.dart';
import 'refresh_manager.dart';
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
  List<DocumentSnapshot> _allSearchResults = [];
  bool _isLoading = false;
  bool _isAiLoading = false;
  bool _showAiButton = false;
  bool _isLoadingMore = false;
  String _lastSearchQuery = '';
  int _currentDisplayCount = 10;
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
        _allSearchResults = [];
        _currentDisplayCount = 10;
      });
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      List<DocumentSnapshot> results = await _performEfficientSearch(query, limit: 100);
      
      setState(() {
        _allSearchResults = results;
        _currentDisplayCount = 10;
        _foods = results.take(_currentDisplayCount).toList();
        _isLoading = false;
        _showAiButton = results.isEmpty && query.isNotEmpty;
        _lastSearchQuery = query;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Search failed');
    }
  }

  Future<List<DocumentSnapshot>> _performEfficientSearch(String query, {int limit = 100}) async {
    final String lowerQuery = query.toLowerCase().trim();
    final String upperQuery = query.toUpperCase();
    final String capitalizedQuery = query.substring(0, 1).toUpperCase() + 
        (query.length > 1 ? query.substring(1).toLowerCase() : '');
    
    final Map<String, DocumentSnapshot> uniqueResults = {};
    
    // Exact match
    final exactMatch = await FirebaseFirestore.instance
        .collection('Food')
        .where('FoodName', isEqualTo: query)
        .limit(10)
        .get();
    
    for (var doc in exactMatch.docs) {
      uniqueResults[doc.id] = doc;
    }
    
    // Multiple case variations matching
    final searchVariations = [query, lowerQuery, upperQuery, capitalizedQuery];
    
    for (String searchTerm in searchVariations) {
      final startsWithQuery = await FirebaseFirestore.instance
          .collection('Food')
          .where('FoodName', isGreaterThanOrEqualTo: searchTerm)
          .where('FoodName', isLessThanOrEqualTo: '$searchTerm\uf8ff')
          .limit(30)
          .get();
      
      for (var doc in startsWithQuery.docs) {
        uniqueResults[doc.id] = doc;
      }
    }
    
    // Smart multi-word search
    if (uniqueResults.length < 10) {
      await _performMultiWordSearch(query, uniqueResults);
    }
    
    // Keyword search
    if (uniqueResults.length < 10) {
      final keywords = _generateSearchKeywords(query);
      
      for (String keyword in keywords.take(5)) {
        try {
          final keywordQuery = await FirebaseFirestore.instance
              .collection('Food')
              .where('SearchKeywords', arrayContains: keyword.toLowerCase())
              .limit(25)
              .get();
          
          for (var doc in keywordQuery.docs) {
            uniqueResults[doc.id] = doc;
          }
        } catch (e) {
          print('SearchKeywords field not found, skipping array-contains search');
        }
      }
    }
    
    // Full search as fallback option
    if (uniqueResults.length < 5) {
      final fallbackQuery = await FirebaseFirestore.instance
          .collection('Food')
          .limit(200)
          .get();
      
      final filtered = fallbackQuery.docs.where((doc) {
        String name = (doc['FoodName'] ?? '').toString().toLowerCase();
        return _isMatchingFoodName(name, lowerQuery);
      }).take(20);
      
      for (var doc in filtered) {
        uniqueResults[doc.id] = doc;
      }
    }
    
    final sortedResults = uniqueResults.values.toList();
    sortedResults.sort((a, b) {
      String nameA = (a['FoodName'] ?? '').toString().toLowerCase();
      String nameB = (b['FoodName'] ?? '').toString().toLowerCase();
      
      // Calculate match score
      double scoreA = _calculateMatchScore(nameA, lowerQuery);
      double scoreB = _calculateMatchScore(nameB, lowerQuery);
      
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // 降序排列，分数高的在前
      }
      
      return nameA.compareTo(nameB);
    });
    
    return sortedResults.take(limit).toList();
  }

  // Smart multi-word search
  Future<void> _performMultiWordSearch(String query, Map<String, DocumentSnapshot> uniqueResults) async {
    final words = query.toLowerCase().trim().split(' ').where((w) => w.isNotEmpty).toList();
    
    if (words.length <= 1) return;
    
    // Get more data for local filtering
    final allFoodsQuery = await FirebaseFirestore.instance
        .collection('Food')
        .limit(200)
        .get();
    
    for (var doc in allFoodsQuery.docs) {
      String foodName = (doc['FoodName'] ?? '').toString().toLowerCase();
      
      // Remove punctuation and normalize the food name for better matching
      String normalizedFoodName = foodName.replaceAll(RegExp(r'[,\-_\.]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      
      // Check if contains all keywords (order independent)
      bool containsAllWords = words.every((word) => normalizedFoodName.contains(word));
      
      if (containsAllWords) {
        uniqueResults[doc.id] = doc;
      }
    }
  }
  
  // Smart matching judgment
  bool _isMatchingFoodName(String foodName, String query) {
    final queryWords = query.split(' ').where((w) => w.isNotEmpty).toList();
    
    // Normalize food name by removing punctuation
    String normalizedFoodName = foodName.replaceAll(RegExp(r'[,\-_\.]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // Single word matching
    if (queryWords.length == 1) {
      return normalizedFoodName.contains(query);
    }
    
    // Multi-word matching - must contain all keywords (order independent)
    return queryWords.every((word) => normalizedFoodName.contains(word.toLowerCase()));
  }
  
  // 计算匹配分数
  double _calculateMatchScore(String foodName, String query) {
    double score = 0.0;
    
    // Normalize food name and query by removing punctuation
    String normalizedFoodName = foodName.replaceAll(RegExp(r'[,\-_\.]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    String normalizedQuery = query.replaceAll(RegExp(r'[,\-_\.]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // Exact match gets highest score
    if (normalizedFoodName == normalizedQuery) {
      return 100.0;
    }
    
    // Starts with match gets high score
    if (normalizedFoodName.startsWith(normalizedQuery)) {
      score += 80.0;
    }
    
    // Contains match
    if (normalizedFoodName.contains(normalizedQuery)) {
      score += 60.0;
    }
    
    final queryWords = normalizedQuery.split(' ').where((w) => w.isNotEmpty).toList();
    if (queryWords.length > 1) {
      // Multi-word search scoring
      int matchedWords = 0;
      int totalWords = queryWords.length;
      
      for (String word in queryWords) {
        if (normalizedFoodName.contains(word)) {
          matchedWords++;
          // Extra points if word is at the beginning
          if (normalizedFoodName.startsWith(word)) {
            score += 20.0;
          } else {
            score += 10.0;
          }
        }
      }
      
      // Extra bonus for matching all words
      if (matchedWords == totalWords) {
        score += 30.0;
      }
      
      // Match ratio score
      score += (matchedWords / totalWords) * 20.0;
    }
    
    // Length factor (shorter names get priority)
    double lengthFactor = 100.0 / (normalizedFoodName.length + 1);
    score += lengthFactor * 0.1;
    
    return score;
  }

  List<String> _generateSearchKeywords(String query) {
    final keywords = <String>[];
    final words = query.toLowerCase().split(' ').where((w) => w.isNotEmpty).toList();
    
    keywords.addAll(words);
    
    for (String word in words) {
      if (word.length > 2) {
        for (int i = 2; i <= word.length; i++) {
          keywords.add(word.substring(0, i));
        }
      }
    }
    
    return keywords.toSet().toList();
  }

  void _loadMoreResults() async {
    if (_isLoadingMore || _allSearchResults.length <= _currentDisplayCount) return;
    
    setState(() => _isLoadingMore = true);
    
    await Future.delayed(const Duration(milliseconds: 300)); // Reduce loading delay
    
    setState(() {
      _currentDisplayCount = (_currentDisplayCount + 15).clamp(0, _allSearchResults.length); // Increase loading count per batch
      _foods = _allSearchResults.take(_currentDisplayCount).toList();
      _isLoadingMore = false;
    });
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

    bool hasMoreResults = _allSearchResults.length > _currentDisplayCount;
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _foods.length + (hasMoreResults ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < _foods.length) {
          final food = _foods[index];
          return _buildFoodCard(food, index);
        } else {
          // 显示更多按钮
          return _buildLoadMoreButton();
        }
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

  Widget _buildLoadMoreButton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20, top: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoadingMore ? null : _loadMoreResults,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: primaryGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primaryGreen.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoadingMore) ...[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(primaryGreen),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Loading more...',
                    style: TextStyle(
                      color: primaryGreen,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else ...[
                  Icon(Icons.expand_more, color: primaryGreen, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Show more results (${_allSearchResults.length - _currentDisplayCount})',
                    style: TextStyle(
                      color: primaryGreen,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
      builder: (context) => _FoodModalWidget(
        food: food,
        onSave: _saveFoodToFirebase,
        onError: _showErrorSnackBar,
      ),
    );
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

  Future<void> _getFoodNutritionFromAI(String foodName) async {
    setState(() {
      _isAiLoading = true;
    });

    try {
      final prompt = '''
Please provide nutrition information for the food '$foodName' based on a standard serving size (approximately 100 grams).
Please return in JSON format with the following fields:
- calories: Calories (kcal)
- protein: Protein (g)
- carbs: Carbohydrates (g)
- fat: Fat (g)
- unit: 100 (fixed value)

Example format:
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

  Map<String, dynamic>? _parseNutritionData(String aiResponse) {
    try {
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

  Future<void> _addFoodToDatabase(String foodName, Map<String, dynamic> nutritionData) async {
    try {
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
          RefreshManagerHelper.refreshAfterLogFood();
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      _showErrorSnackBar('Error saving food: $e');
    }
  }

  int _extractNumericFromUnit(String unitString) {
    final RegExp numberRegex = RegExp(r'(\d+)');
    final match = numberRegex.firstMatch(unitString);
    return match != null ? int.parse(match.group(1)!) : 100;
  }
}

// 独立的食物模态框组件，使用StatefulWidget来管理自己的状态
class _FoodModalWidget extends StatefulWidget {
  final DocumentSnapshot food;
  final Function(DocumentSnapshot, int, double, double, double, double) onSave;
  final Function(String) onError;

  const _FoodModalWidget({
    required this.food,
    required this.onSave,
    required this.onError,
  });

  @override
  State<_FoodModalWidget> createState() => _FoodModalWidgetState();
}

class _FoodModalWidgetState extends State<_FoodModalWidget> {
  late TextEditingController _qtyController;
  double _quantity = 0.0;
  late int _dbQty;
  late double _cal, _carb, _protein, _fat;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController();
    
    // 初始化营养数据
    String unitString = (widget.food['Unit'] ?? '100g').toString();
    _dbQty = _extractNumericFromUnit(unitString);
    _cal = (widget.food['Calories'] ?? 0).toDouble();
    _carb = (widget.food['Carbohydrates'] ?? 0).toDouble();
    _protein = (widget.food['Protein'] ?? 0).toDouble();
    _fat = (widget.food['Fat'] ?? 0).toDouble();
    
    // 监听文本变化
    _qtyController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final newValue = double.tryParse(_qtyController.text) ?? 0.0;
    if (_quantity != newValue) {
      setState(() {
        _quantity = newValue;
      });
    }
  }

  int _extractNumericFromUnit(String unitString) {
    final RegExp numberRegex = RegExp(r'(\d+)');
    final match = numberRegex.firstMatch(unitString);
    return match != null ? int.parse(match.group(1)!) : 100;
  }

  @override
  Widget build(BuildContext context) {
    // 计算营养值
    double ratio = (_quantity > 0) ? _quantity / _dbQty : 0;
    double showCal = _cal * ratio;
    double showCarb = _carb * ratio;
    double showProtein = _protein * ratio;
    double showFat = _fat * ratio;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
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
                      colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
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
                        widget.food['FoodName'] ?? 'Unknown Food',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E2E2E),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        (widget.food['Unit'] ?? '100g').toString(),
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF757575),
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
                color: Color(0xFFF8F9FA),
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
                color: Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.scale_rounded, color: Color(0xFF4CAF50), size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Quantity (g):',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E2E2E),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _qtyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.done,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E2E2E),
                      ),
                      validator: (value) {
                         if (value == null || value.isEmpty) {
                           return 'Please enter weight';
                         }
                         final quantity = double.tryParse(value);
                         if (quantity == null || quantity < 0.1) {
                           return 'Minimum 0.1g required';
                         }
                         return null;
                       },
                      decoration: InputDecoration(
                        hintText: 'Enter weight (g)',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Color(0xFF4CAF50).withOpacity(0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Color(0xFF4CAF50), width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.red, width: 1),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.red, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onFieldSubmitted: (value) {
                        // 确保提交时数值保持
                        FocusScope.of(context).unfocus();
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
                  if (_quantity < 0.1) {
                    widget.onError('Please enter a valid weight (minimum 0.1g)!');
                    return;
                  }

                  double ratio = (_quantity > 0) ? _quantity / _dbQty : 0;
                  double finalCal = _cal * ratio;
                  double finalCarb = _carb * ratio;
                  double finalProtein = _protein * ratio;
                  double finalFat = _fat * ratio;

                  Navigator.pop(context);
                  await widget.onSave(
                    widget.food,
                    _quantity.round(),
                    finalCal,
                    finalProtein,
                    finalCarb,
                    finalFat,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF4CAF50),
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
  }

  Widget _buildNutrientCard(String label, String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
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
              color: Color(0xFF757575),
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
                    color: Color(0xFF757575),
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
}















































