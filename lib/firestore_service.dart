// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

class FirestoreService {
  // Load JSON data from local assets
  static Future<Map<String, dynamic>> loadFoodData() async {
    final jsonString = await rootBundle.loadString('assets/foods.json');
    return jsonDecode(jsonString);
  }

  // Upload data to Firestore
  static Future<void> uploadToFirestore() async {
    try {
      final foodData = await loadFoodData();
      final firestore = FirebaseFirestore.instance;
      final foods = foodData['Foods'] as List<dynamic>;

      for (final food in foods) {
        await firestore.collection('Food').add({
          'FoodID': food['FoodID'],
          'FoodName': food['FoodName'],
          'Calories': food['Calories'],
          'Protein': food['Protein'],
          'Carbohydrates': food['Carbohydrates'],
          'Fat': food['Fat'],
          'Unit': food['Unit'],
        });
      }
      print('Data uploaded successfully!');
    } catch (e) {
      print('Upload failed: $e');
    }
  }
}