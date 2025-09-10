import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:caloriecare/streak_service.dart';
import 'package:caloriecare/streak_page.dart';
import 'package:caloriecare/user_model.dart';
import 'package:caloriecare/homepage.dart';
import 'package:caloriecare/loading_utils.dart';
import 'package:caloriecare/refresh_manager.dart';
import 'package:caloriecare/session_service.dart';

// 性能监控工具
class PerformanceMonitor {
  static final Map<String, DateTime> _startTimes = {};
  
  static void startTimer(String name) {
    _startTimes[name] = DateTime.now();
    print('⏱️ Started: $name');
  }
  
  static void endTimer(String name) {
    final startTime = _startTimes[name];
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime);
      print('⏱️ Completed: $name - ${duration.inMilliseconds}ms');
      _startTimes.remove(name);
    }
  }
}

class RecogniteFoodPage extends StatefulWidget {
  final String mealType;
  final String? userId;
  final UserModel? user;
  final DateTime? selectedDate; // Add selectedDate parameter

  const RecogniteFoodPage({
    Key? key,
    required this.mealType,
    this.userId,
    this.user,
    this.selectedDate, // Add to constructor
  }) : super(key: key);

  @override
  State<RecogniteFoodPage> createState() => _RecogniteFoodPageState();
}

class _RecogniteFoodPageState extends State<RecogniteFoodPage> {
  File? _imageFile;
  bool _isAnalyzing = false;
  List<Map<String, dynamic>> _foodList = [];
  List<bool> _selected = [];
  List<int> _selectedMatchIndex = [];
  final ImagePicker _picker = ImagePicker();

  // Gemini API Key
  final String _geminiApiKey = dotenv.env['GEMINI_API_KEY']!;
  final String _geminiApiUrlBase = dotenv.env['GEMINI_API_URL']!;

  // 缓存数据库食物列表
  static List<Map<String, dynamic>>? _cachedDbFoods;
  static DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(minutes: 30);

  // 获取缓存的数据库食物列表
  Future<List<Map<String, dynamic>>> _getCachedDbFoods() async {
    final now = DateTime.now();
    
    // 如果缓存存在且未过期，直接返回
    if (_cachedDbFoods != null && _lastCacheTime != null &&
        now.difference(_lastCacheTime!) < _cacheValidDuration) {
      return _cachedDbFoods!;
    }

    // 否则从数据库获取并缓存
    try {
      final foodsCollection = FirebaseFirestore.instance.collection('Food');
      final snapshot = await foodsCollection.get();
      
      _cachedDbFoods = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'FoodID': data['FoodID']?.toString() ?? '',
          'FoodName': data['FoodName']?.toString() ?? '',
          'Unit': data['Unit']?.toString() ?? '',
          'Calories': safeToDouble(data['Calories']),
          'Protein': safeToDouble(data['Protein']),
          'Carbohydrates': safeToDouble(data['Carbohydrates']),
          'Fat': safeToDouble(data['Fat']),
        };
      }).toList();
      
      _lastCacheTime = now;
      return _cachedDbFoods!;
    } catch (e) {
      print('Error fetching database foods: $e');
      // 如果获取失败但有缓存，返回旧缓存
      if (_cachedDbFoods != null) {
        return _cachedDbFoods!;
      }
      rethrow;
    }
  }

  // 压缩图片
  Future<Uint8List> _compressImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      
      // 如果图片小于500KB，直接返回
      if (bytes.length < 500 * 1024) {
        return bytes;
      }

      // 解码图片
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 800, // 限制宽度
        targetHeight: 800, // 限制高度
      );
      
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      
      if (data != null) {
        return data.buffer.asUint8List();
      }
      
      return bytes;
    } catch (e) {
      print('Error compressing image: $e');
      // 如果压缩失败，返回原图片
      return await imageFile.readAsBytes();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
        _foodList = [];
        _selected = [];
      });
      _analyzeNutrition();
    }
  }

  Future<void> _analyzeNutrition() async {
    if (_imageFile == null) return;
    
    PerformanceMonitor.startTimer('total_analysis');
    
    setState(() {
      _foodList = [];
      _selected = [];
      _isAnalyzing = true;
    });

    try {
      await LoadingUtils.showLoadingWhile(
        context,
        () async {
          PerformanceMonitor.startTimer('get_cached_foods');
          // 获取缓存的数据库食物列表
          final dbFoods = await _getCachedDbFoods();
          PerformanceMonitor.endTimer('get_cached_foods');
          
          // 构建数据库食物列表字符串（限制数量以提高性能）
          final limitedDbFoods = dbFoods.take(500).toList(); // 限制前500个食物
          final String dbFoodsList = limitedDbFoods.map((food) => 
            '${food['FoodName']} (${food['Unit']}) - Calories: ${food['Calories']}, Protein: ${food['Protein']}g, Carbs: ${food['Carbohydrates']}g, Fat: ${food['Fat']}g'
          ).join('\n');

          PerformanceMonitor.startTimer('compress_image');
          // 压缩图片
          final compressedBytes = await _compressImage(_imageFile!);
          final String base64Image = base64Encode(compressedBytes);
          PerformanceMonitor.endTimer('compress_image');

          final String prompt = '''
You are a nutritionist analyzing food images. Please follow this three-step process:

STEP 0: First, examine the image carefully and determine if there are any food items present in the image. If you do not see any food items (e.g., the image contains only non-food objects like tables, people, landscapes, etc.), respond with exactly: "NO_FOOD_DETECTED"

STEP 1: If food is detected, analyze the image and identify what foods you actually see in the image. Provide detailed nutritional information for each food item you identify.

STEP 2: Then, I will provide you with a food database, and you should check if any of your identified foods match items in the database.

For now, please complete STEP 0 and STEP 1 only. First check if there is food in the image, then if food is present, analyze and provide detailed nutritional information for each food item you identify.

If NO food is detected, respond with: "NO_FOOD_DETECTED"

If food IS detected, provide for each distinct food item identified, ONLY the following format:

**Food Item 1: [What you actually see in the image - be specific and descriptive]**
- Portion: [number]g or [number]ml
- Kcal: [Kcal Value]
- Protein: [Protein Value]g
- Fat: [Fat Value]g
- Carbs: [Carbs Value]g

Rules:
1. Only use grams (g) or milliliters (ml) as units
2. Do NOT use other units like "slice", "cup", "fillet", "spears", etc.
3. If you cannot estimate portion in g or ml, skip that food item
4. Do NOT add any notes, disclaimers, or explanations
5. Provide only the food items and their nutritional data in the exact format shown above
6. Be as accurate as possible about what you actually see in the image
7. Use descriptive names that clearly identify the food (e.g., "Nasi Lemak with coconut rice", "Fried chicken with curry sauce")
8. If no food is detected, respond ONLY with "NO_FOOD_DETECTED"

''';

          final Map<String, dynamic> requestBody = {
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                  {
                    'inlineData': {
                      'mimeType': 'image/jpeg',
                      'data': base64Image,
                    }
                  }
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.3,
              'topP': 1,
              'topK': 32,
              'maxOutputTokens': 1024, // 减少token数量以提高速度
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
          
          PerformanceMonitor.startTimer('api_request');
          // 添加超时和重试机制
          final response = await _makeApiRequestWithRetry(fullApiUrl, requestBody);
          PerformanceMonitor.endTimer('api_request');

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
            print('Gemini raw result: $generatedContent');
            
            // Check if no food was detected
            if (generatedContent.trim().contains('NO_FOOD_DETECTED')) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('No food items detected in the image. Please take a photo containing food or use manual search instead.'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 5),
                  action: SnackBarAction(
                    label: 'Manual Search',
                    textColor: Colors.white,
                    onPressed: () {
                      // Navigate to manual search or show search dialog
                      _showManualSearchDialog();
                    },
                  ),
                ),
              );
              return;
            }
            
            PerformanceMonitor.startTimer('parse_result');
            final foods = _parseGeminiResult(generatedContent);
            PerformanceMonitor.endTimer('parse_result');
            
            PerformanceMonitor.startTimer('match_database');
            await _matchFoodsWithDatabase(foods);
            PerformanceMonitor.endTimer('match_database');
          } else {
            throw Exception('API Error: ${response.statusCode} - ${response.body}');
          }
        },
        message: 'Analyzing food...',
      );
      
      PerformanceMonitor.endTimer('total_analysis');
    } catch (e) {
      print('Error in _analyzeNutrition: $e');
      String errorMessage = 'Failed to identify';
      
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
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _analyzeNutrition(),
          ),
        ),
      );
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  // 带重试机制的API请求
  Future<http.Response> _makeApiRequestWithRetry(String url, Map<String, dynamic> body) async {
    const int maxRetries = 3;
    const Duration timeout = Duration(seconds: 30);
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(timeout);
        
        return response;
      } catch (e) {
        print('API request attempt $attempt failed: $e');
        
        if (attempt == maxRetries) {
          rethrow;
        }
        
        // 等待一段时间后重试
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    
    throw Exception('All retry attempts failed');
  }

  double _parseDoubleValue(String input) {
    // 提取所有数字（包括小数），如 "300-350" -> [300, 350]
    final matches = RegExp(r'(\d+(\.\d+)?)').allMatches(input);
    if (matches.isEmpty) return 0;
    if (matches.length == 2) {
      final n1 = double.parse(matches.elementAt(0).group(0)!);
      final n2 = double.parse(matches.elementAt(1).group(0)!);
      return ((n1 + n2) / 2);
    }
    return double.parse(matches.first.group(0)!);
  }

  List<Map<String, dynamic>> _parseGeminiResult(String content) {
    final lines = content.split('\n');
    List<Map<String, dynamic>> foods = [];
    Map<String, dynamic> current = {};
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      if (line.contains('Food Name') || line.contains('Food Item')) {
        if (current.isNotEmpty) foods.add(current);
        current = {};
        final name = line.contains(':') ? line.split(':').last.trim().replaceAll('*', '') : '';
        current['name'] = name;
      } else if (line.toLowerCase().contains('portion')) {
        // 只提取带g/ml的数字
        final portionMatch = RegExp(r'(\d+(\.\d+)?)(\s?)(g|ml)').firstMatch(line.toLowerCase());
        if (portionMatch != null) {
          current['portion'] = portionMatch.group(0)!.replaceAll(' ', '');
        } else {
          current['portion'] = ''; // 没有g/ml就设为空
        }
      } else if (line.toLowerCase().contains('kcal')) {
        if (line.toLowerCase().contains('negligible')) {
          current['kcal'] = 0;
        } else {
          current['kcal'] = _parseDoubleValue(line);
        }
      } else if (line.toLowerCase().contains('protein')) {
        if (line.toLowerCase().contains('negligible')) {
          current['protein'] = 0;
        } else {
          current['protein'] = _parseDoubleValue(line);
        }
      } else if (line.toLowerCase().contains('fat')) {
        if (line.toLowerCase().contains('negligible')) {
          current['fat'] = 0;
        } else {
          current['fat'] = _parseDoubleValue(line);
        }
      } else if (line.toLowerCase().contains('carb')) {
        if (line.toLowerCase().contains('negligible')) {
          current['carbs'] = 0;
        } else {
          current['carbs'] = _parseDoubleValue(line);
        }
      }
    }
    if (current.isNotEmpty) foods.add(current);

    // Filter out foods with no g/ml portion, no name, or all nutritional values are 0
    final filteredFoods = foods.where((f) =>
    (f['name'] ?? '').isNotEmpty &&
        (f['portion'] ?? '').isNotEmpty &&
        ((f['kcal'] ?? 0) > 0 || (f['protein'] ?? 0) > 0 || (f['fat'] ?? 0) > 0 || (f['carbs'] ?? 0) > 0)
    ).toList();

    // Merge foods with the same name
    final Map<String, Map<String, dynamic>> mergedFoods = {};
    
    for (var food in filteredFoods) {
      final name = food['name']?.toString().toLowerCase().trim() ?? '';
      if (name.isEmpty) continue;
      
      if (mergedFoods.containsKey(name)) {
        // Merge same-named foods
        final existing = mergedFoods[name]!;
        
        // Merge portions
        final existingPortion = _extractGrams(existing['portion'] ?? '0g');
        final newPortion = _extractGrams(food['portion'] ?? '0g');
        final totalPortion = existingPortion + newPortion;
        existing['portion'] = '${totalPortion.toStringAsFixed(0)}g';
        
        // Merge nutritional values
        existing['kcal'] = (existing['kcal'] ?? 0) + (food['kcal'] ?? 0);
        existing['protein'] = (existing['protein'] ?? 0) + (food['protein'] ?? 0);
        existing['fat'] = (existing['fat'] ?? 0) + (food['fat'] ?? 0);
        existing['carbs'] = (existing['carbs'] ?? 0) + (food['carbs'] ?? 0);
      } else {
        mergedFoods[name] = Map<String, dynamic>.from(food);
      }
    }
    
    return mergedFoods.values.toList();
  }

  double _extractGrams(String portion) {
    final match = RegExp(r'(\d+(\.\d+)?)').firstMatch(portion);
    return match != null ? double.parse(match.group(0)!) : 0.0;
  }

  Future<void> _matchFoodsWithDatabase(List<Map<String, dynamic>> foods) async {
    // 使用缓存的数据库食物列表
    final cachedDbFoods = await _getCachedDbFoods();
    
    final dbFoods = cachedDbFoods.map((food) {
      return {
        'id': food['FoodID'] ?? '',
        'FoodID': food['FoodID'] ?? '',
        'name': food['FoodName'] ?? '',
        'unit': food['Unit'] ?? '',
        'calories': food['Calories'] ?? 0.0,
        'protein': food['Protein'] ?? 0.0,
        'carbs': food['Carbohydrates'] ?? 0.0,
        'fat': food['Fat'] ?? 0.0,
      };
    }).toList();

    List<Map<String, dynamic>> result = [];
    for (var food in foods) {
      if ((food['name'] ?? '').isEmpty) continue;

      // 使用更智能的匹配算法
      var bestMatch = _findBestMatch(food['name'], dbFoods);
      
      if (bestMatch != null && bestMatch['score'] > 70) { // 设置匹配阈值
        // Found a good match, use database data
        final dbFood = bestMatch['food'];
        final portionString = food['portion']?.toString() ?? '100g';
        final portionMatch = RegExp(r'(\d+(\.\d+)?)').firstMatch(portionString);
        final portionGrams = portionMatch != null ? double.parse(portionMatch.group(0)!) : 100.0;

        final unitString = dbFood['unit']?.toString() ?? '100g';
        final unitMatch = RegExp(r'(\d+(\.\d+)?)').firstMatch(unitString);
        final unitGrams = unitMatch != null ? double.parse(unitMatch.group(0)!) : 100.0;

        final factor = unitGrams > 0 ? portionGrams / unitGrams : 0;
        
        result.add({
          'id': dbFood['id'],
          'FoodID': dbFood['FoodID'],
          'name': dbFood['name'],
          'portion': food['portion'],
          'calories': (dbFood['calories'] as double? ?? 0.0) * factor,
          'protein': (dbFood['protein'] as double? ?? 0.0) * factor,
          'carbs': (dbFood['carbs'] as double? ?? 0.0) * factor,
          'fat': (dbFood['fat'] as double? ?? 0.0) * factor,
          'fromDb': true,
          'originalName': food['name'],
          'matchScore': bestMatch['score'],
          'allMatches': [{
            'id': dbFood['id'],
            'FoodID': dbFood['FoodID'],
            'name': dbFood['name'],
            'calories': (dbFood['calories'] as double? ?? 0.0) * factor,
            'protein': (dbFood['protein'] as double? ?? 0.0) * factor,
            'carbs': (dbFood['carbs'] as double? ?? 0.0) * factor,
            'fat': (dbFood['fat'] as double? ?? 0.0) * factor,
            'score': bestMatch['score'],
          }],
        });
      } else {
        // No good match found, use data recognized by AI
        result.add({
          'id': '',
          'FoodID': '',
          'name': food['name'],
          'portion': food['portion'],
          'calories': food['kcal'] ?? 0,
          'protein': food['protein'] ?? 0,
          'carbs': food['carbs'] ?? 0,
          'fat': food['fat'] ?? 0,
          'fromDb': false,
          'originalName': food['name'],
          'matchScore': 0,
          'allMatches': [],
        });
      }
    }

    setState(() {
      _foodList = result;
      _selected = List.generate(result.length, (index) => true);
      _selectedMatchIndex = List.generate(result.length, (index) => 0);
    });
  }

  // 智能匹配算法
  Map<String, dynamic>? _findBestMatch(String foodName, List<Map<String, dynamic>> dbFoods) {
    if (foodName.isEmpty) return null;
    
    String normalizedFoodName = foodName.toLowerCase().trim();
    Map<String, dynamic>? bestMatch;
    double bestScore = 0;
    
    for (var dbFood in dbFoods) {
      String dbFoodName = dbFood['name'].toString().toLowerCase().trim();
      
      // 计算匹配分数
      double score = _calculateSimilarity(normalizedFoodName, dbFoodName);
      
      if (score > bestScore) {
        bestScore = score;
        bestMatch = {
          'food': dbFood,
          'score': score,
        };
      }
    }
    
    return bestMatch;
  }

  // 计算字符串相似度
  double _calculateSimilarity(String str1, String str2) {
    if (str1 == str2) return 100.0;
    
    // 标准化字符串：移除标点符号，转换为小写，分割单词
    String normalizedStr1 = str1.toLowerCase().replaceAll(RegExp(r'[,\-_\.]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    String normalizedStr2 = str2.toLowerCase().replaceAll(RegExp(r'[,\-_\.]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // 完全匹配（标准化后）
    if (normalizedStr1 == normalizedStr2) return 100.0;
    
    List<String> words1 = normalizedStr1.split(' ').where((w) => w.isNotEmpty && w.length > 1).toList();
    List<String> words2 = normalizedStr2.split(' ').where((w) => w.isNotEmpty && w.length > 1).toList();
    
    if (words1.isEmpty || words2.isEmpty) return 0.0;
    
    // 计算词汇匹配分数
    int exactMatches = 0;
    int partialMatches = 0;
    
    for (String word1 in words1) {
      bool foundExactMatch = false;
      bool foundPartialMatch = false;
      
      for (String word2 in words2) {
        if (word1 == word2) {
          exactMatches++;
          foundExactMatch = true;
          break;
        } else if (!foundPartialMatch && (word1.contains(word2) || word2.contains(word1))) {
          partialMatches++;
          foundPartialMatch = true;
        }
      }
    }
    
    // 计算匹配率
    double exactMatchRatio = exactMatches / words1.length;
    double partialMatchRatio = partialMatches / words1.length;
    double totalMatchRatio = exactMatchRatio + (partialMatchRatio * 0.7); // 部分匹配权重较低
    
    // 基础分数
    double baseScore = totalMatchRatio * 100;
    
    // 如果所有查询词都能在目标字符串中找到（不考虑顺序），给予高分
    bool allWordsFound = words1.every((word1) => 
        words2.any((word2) => word1 == word2 || word1.contains(word2) || word2.contains(word1)));
    
    if (allWordsFound) {
      baseScore = max(baseScore, 85.0); // 确保所有词匹配时得到高分
    }
    
    // 长度相似性奖励
    double lengthSimilarity = 1.0 - (normalizedStr1.length - normalizedStr2.length).abs() / max(normalizedStr1.length, normalizedStr2.length);
    baseScore += lengthSimilarity * 10;
    
    // 检查字符串包含关系
    if (normalizedStr1.contains(normalizedStr2) || normalizedStr2.contains(normalizedStr1)) {
      baseScore = max(baseScore, 80.0);
    }
    
    return min(100.0, baseScore);
  }

  // 计算编辑距离
  int _calculateEditDistance(String str1, String str2) {
    int len1 = str1.length;
    int len2 = str2.length;
    
    List<List<int>> dp = List.generate(
      len1 + 1, 
      (i) => List.generate(len2 + 1, (j) => 0)
    );
    
    for (int i = 0; i <= len1; i++) {
      dp[i][0] = i;
    }
    for (int j = 0; j <= len2; j++) {
      dp[0][j] = j;
    }
    
    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        if (str1[i - 1] == str2[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] = 1 + min(dp[i - 1][j], min(dp[i][j - 1], dp[i - 1][j - 1]));
        }
      }
    }
    
    return dp[len1][len2];
  }

  Future<void> _addSelectedFoods() async {
    final userId = widget.userId;
    if (userId == null) return;

    // Use selected date instead of today
    final targetDate = widget.selectedDate ?? DateTime.now();
    final targetDateStr = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

    // Check if this is today's date for streak update eligibility
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final isLoggingForToday = targetDateStr == todayStr;

    // BEFORE adding any food, check if user has already logged any food for TODAY
    final existingLogsToday = await FirebaseFirestore.instance
        .collection('LogMeal')
        .where('UserID', isEqualTo: userId)
        .where('LogDate', isEqualTo: todayStr)
        .get();

    bool isFirstLogOfToday = existingLogsToday.docs.isEmpty;

    // Find/create LogMeal for the target date
    final logMealQuery = await FirebaseFirestore.instance
        .collection('LogMeal')
        .where('UserID', isEqualTo: userId)
        .where('LogDate', isEqualTo: targetDateStr)
        .where('MealType', isEqualTo: widget.mealType)
        .get();

    String logID;
    if (logMealQuery.docs.isNotEmpty) {
      logID = logMealQuery.docs.first['LogID'];
    } else {
      // New LogID
      final lastLog = await FirebaseFirestore.instance
          .collection('LogMeal')
          .orderBy('LogID', descending: true)
          .limit(1)
          .get();
      int newNum = 1;
      if (lastLog.docs.isNotEmpty) {
        final lastId = lastLog.docs.first['LogID'];
        newNum = int.parse(lastId.substring(1)) + 1;
      }
      logID = 'L${newNum.toString().padLeft(5, '0')}';
      await FirebaseFirestore.instance.collection('LogMeal').add({
        'LogID': logID,
        'UserID': userId,
        'LogDate': targetDateStr,
        'MealType': widget.mealType,
        'TotalCalories': 0,
        'TotalProtein': 0,
        'TotalCarbs': 0,
        'TotalFat': 0,
      });
    }

    // Process selected foods
    for (int i = 0; i < _foodList.length; i++) {
      if (!_selected[i]) continue;
      final food = _foodList[i];
      String foodIdToAdd;

      if (food['fromDb'] == true) {
        foodIdToAdd = food['FoodID'];
      } else {
        // New food, add to 'foods' collection first
        final portionMatch = RegExp(r'(\d+(\.\d+)?)').firstMatch(food['portion'] ?? '');
        final portionGrams = portionMatch != null ? double.parse(portionMatch.group(0)!) : 100.0;

        final caloriesPer100g = portionGrams > 0 ? (food['calories'] / portionGrams * 100) : 0;
        final proteinPer100g = portionGrams > 0 ? (food['protein'] / portionGrams * 100) : 0;
        final fatPer100g = portionGrams > 0 ? (food['fat'] / portionGrams * 100) : 0;
        final carbsPer100g = portionGrams > 0 ? (food['carbs'] / portionGrams * 100) : 0;

        final cleanName = (food['name'] ?? '').replaceAll(RegExp(r'\*+'), '').trim();

        final lastFood = await FirebaseFirestore.instance
            .collection('Food')
            .orderBy('FoodID', descending: true)
            .limit(1)
            .get();

        int newFoodNum = 1;
        if (lastFood.docs.isNotEmpty) {
          final lastFoodId = lastFood.docs.first['FoodID'];
          newFoodNum = int.parse(lastFoodId.substring(1)) + 1;
        }
        final newFoodID = 'F${newFoodNum.toString().padLeft(5, '0')}';

        await FirebaseFirestore.instance.collection('Food').add({
          'FoodID': newFoodID,
          'FoodName': cleanName,
          'Unit': 'per 100g',
          'Calories': caloriesPer100g,
          'Protein': double.parse(proteinPer100g.toStringAsFixed(2)),
          'Carbohydrates': double.parse(carbsPer100g.toStringAsFixed(2)),
          'Fat': double.parse(fatPer100g.toStringAsFixed(2)),
        });
        foodIdToAdd = newFoodID;
      }

      // Add to LogMealList
      await FirebaseFirestore.instance.collection('LogMealList').add({
        'LogID': logID,
        'FoodID': foodIdToAdd,
        'SubCalories': (food['calories'] as double).round(),
        'SubProtein': double.parse((food['protein'] as double).toStringAsFixed(2)),
        'SubCarbs': double.parse((food['carbs'] as double).toStringAsFixed(2)),
        'SubFat': double.parse((food['fat'] as double).toStringAsFixed(2)),
      });
    }

    // Update total nutrition in LogMeal
    final mealFoods = await FirebaseFirestore.instance
        .collection('LogMealList')
        .where('LogID', isEqualTo: logID)
        .get();
    double totalCal = 0, totalProtein = 0, totalCarbs = 0, totalFat = 0;
    for (var doc in mealFoods.docs) {
      totalCal += (doc['SubCalories'] ?? 0).toDouble();
      totalProtein += (doc['SubProtein'] ?? 0).toDouble();
      totalCarbs += (doc['SubCarbs'] ?? 0).toDouble();
      totalFat += (doc['SubFat'] ?? 0).toDouble();
    }

    // Update logmeal record
    if (logMealQuery.docs.isNotEmpty) {
      // Update existing logmeal record
      await logMealQuery.docs.first.reference.update({
        'TotalCalories': totalCal.round(),
        'TotalProtein': double.parse(totalProtein.toStringAsFixed(2)),
        'TotalCarbs': double.parse(totalCarbs.toStringAsFixed(2)),
        'TotalFat': double.parse(totalFat.toStringAsFixed(2)),
      });
    } else {
      // If it's a newly created LogMeal record, it needs to be updated
      final newLogMealQuery = await FirebaseFirestore.instance
          .collection('LogMeal')
          .where('LogID', isEqualTo: logID)
          .get();
      if (newLogMealQuery.docs.isNotEmpty) {
        await newLogMealQuery.docs.first.reference.update({
          'TotalCalories': totalCal.round(),
          'TotalProtein': double.parse(totalProtein.toStringAsFixed(2)),
          'TotalCarbs': double.parse(totalCarbs.toStringAsFixed(2)),
          'TotalFat': double.parse(totalFat.toStringAsFixed(2)),
        });
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Food added successfully!')),
    );

    // After adding foods, update the streak only if:
    // 1. This is the first food log of TODAY (checked BEFORE adding food)
    // 2. AND we're logging food for today's date (not past/future)
    if (context.mounted) {
      Map<String, dynamic> streakData;
      
      if (isFirstLogOfToday && isLoggingForToday) {
        print('Updating streak: First log of today for current date');
        streakData = await StreakService().updateUserStreak(userId);
      } else {
        print('Skipping streak update: isFirstLogOfToday=$isFirstLogOfToday, isLoggingForToday=$isLoggingForToday');
        // Get current streak without updating
        final streakQuery = await FirebaseFirestore.instance
            .collection('StreakRecord')
            .where('UserID', isEqualTo: userId)
            .limit(1)
            .get();
        
        if (streakQuery.docs.isNotEmpty) {
          final data = streakQuery.docs.first.data();
          streakData = {
            'streakDays': data['CurrentStreakDays'] ?? 0,
            'isNewDay': false,
          };
        } else {
          streakData = {'streakDays': 0, 'isNewDay': false};
        }
      }

      UserModel? currentUser;
      if (widget.user != null) {
        currentUser = widget.user;
      } else {
        currentUser = await SessionService.getUserSession();
      }
      
      // Determine navigation based on streak update
      if (isFirstLogOfToday && isLoggingForToday) {
        // Navigate to streak page only if streak was updated
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
        // If streak was already triggered today, return to previous page
        // 触发刷新
        RefreshManagerHelper.refreshAfterLogFood();
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Food recognition'),
        actions: [
          IconButton(
            icon: Icon(Icons.photo_camera),
            onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.camera),
            tooltip: 'Take a photo',
          ),
          IconButton(
            icon: Icon(Icons.photo_library),
            onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.gallery),
            tooltip: 'Select from album',
          ),
        ],
      ),
      body: _foodList.isEmpty
          ? Center(
              child: Container(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _imageFile == null ? Icons.camera_alt_outlined : Icons.search_off_outlined,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _imageFile == null 
                          ? 'Ready to Recognize Food'
                          : 'No Food Detected',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _imageFile == null 
                          ? 'Take a photo or select an image from your album to get started.'
                          : 'Food not recognized. Please try taking the photo again with better lighting.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_imageFile != null) ...[
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _isAnalyzing ? null : () => _analyzeNutrition(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5AA162),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (_imageFile != null)
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        _imageFile!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _foodList.length,
                    itemBuilder: (context, idx) {
                      final food = _foodList[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          border: Border.all(
                            color: _selected[idx] 
                                ? const Color(0xFF5AA162).withOpacity(0.3)
                                : Colors.grey.shade200,
                            width: _selected[idx] ? 2 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: _selected[idx] 
                                          ? const Color(0xFF5AA162)
                                          : Colors.grey.shade300,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Checkbox(
                                      value: _selected[idx],
                                      onChanged: (v) {
                                        setState(() {
                                          _selected[idx] = v ?? false;
                                        });
                                      },
                                      activeColor: Colors.transparent,
                                      checkColor: Colors.white,
                                      side: BorderSide.none,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                food['name'],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 18,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: food['fromDb'] == true 
                                                      ? [Colors.green.shade400, Colors.green.shade600]
                                                      : [Colors.orange.shade400, Colors.orange.shade600],
                                                ),
                                                borderRadius: BorderRadius.circular(20),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: (food['fromDb'] == true ? Colors.green : Colors.orange).withOpacity(0.3),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    food['fromDb'] == true 
                                                        ? Icons.verified
                                                        : Icons.auto_awesome,
                                                    size: 14,
                                                    color: Colors.white,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    food['fromDb'] == true 
                                                        ? 'Database' 
                                                        : 'AI Generated',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${food['portion']} • ${food['calories'].toStringAsFixed(0)} kcal',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _buildNutrientInfo(
                                        'Protein',
                                        '${food['protein'].toStringAsFixed(1)}g',
                                        Colors.red.shade500,
                                        Icons.fitness_center,
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 40,
                                      color: Colors.grey.shade300,
                                    ),
                                    Expanded(
                                      child: _buildNutrientInfo(
                                        'Carbs',
                                        '${food['carbs'].toStringAsFixed(1)}g',
                                        Colors.orange.shade500,
                                        Icons.grain,
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 40,
                                      color: Colors.grey.shade300,
                                    ),
                                    Expanded(
                                      child: _buildNutrientInfo(
                                        'Fat',
                                        '${food['fat'].toStringAsFixed(1)}g',
                                        Colors.blue.shade500,
                                        Icons.opacity,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (food['fromDb'] == true && food['matchScore'] != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Matched with database (${food['matchScore'].toStringAsFixed(1)}% confidence)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (food['fromDb'] == false)
                                Container(
                                  margin: const EdgeInsets.only(top: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.auto_awesome, color: Colors.orange.shade600, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'AI estimated values - will be added to database',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.orange.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5AA162),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _addSelectedFoods,
                        child: const Text(
                          'Add Selected Foods',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  double safeToDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    try {
      final cleaned = value.toString().replaceAll(RegExp(r'[^0-9\.\-]'), '');
      return double.tryParse(cleaned) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Widget _buildNutrientInfo(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: color,
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  void _showManualSearchDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Manual Food Search'),
          content: Text(
            'No food items were detected in the image. You can:\n\n'
            '• Take a new photo with food items\n'
            '• Use the manual search feature in the Log Food page\n'
            '• Navigate back to the main page and use "Add Food" option',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate back to previous page
                Navigator.of(context).pop();
              },
              child: Text('Go Back'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Take a new photo
                _pickImage(ImageSource.camera);
              },
              child: Text('Take New Photo'),
            ),
          ],
        );
      },
    );
  }
}



