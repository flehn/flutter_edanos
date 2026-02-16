import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'model_config.dart';
import 'services/remote_config_service.dart';
import 'dart:typed_data';

/// Gemini AI service for food image analysis.
///
/// Uses Firebase AI (Google AI) for nutrition analysis.
/// Requires Firebase to be initialized before use (done in main.dart).
///
/// Models:
/// 1. Analysis Model (gemini-2.5-flash) - Image analysis (macros or comprehensive)
/// 2. Search Model (gemini-2.5-flash-lite + GoogleSearch) - Ingredient lookup
/// 3. Evaluation Model (gemini-2.5-flash) - Health evaluation, once a day after 18:00 

class GeminiService {
  static GenerativeModel? _analysisModelEssential;
  static GenerativeModel? _analysisModelComprehensive;
  static GenerativeModel? _searchModel;
  static GenerativeModel? _evaluationModel;
  static GenerativeModel? _progressEvaluationModel;
  static bool _isInitialized = false;

  /// Initialize the Gemini models.
  /// Firebase and RemoteConfigService must be initialized before calling this.
  static Future<void> initialize() async {
    if (_isInitialized) return;

    final analysisModelName = RemoteConfigService.analysisModel;
    final searchModelName = RemoteConfigService.searchModel;
    final evaluationModelName = RemoteConfigService.evaluationModel;

    debugPrint('Gemini models — analysis: $analysisModelName, search: $searchModelName, evaluation: $evaluationModelName');

    final vertexAI = FirebaseAI.vertexAI(location: 'europe-west1', appCheck: FirebaseAppCheck.instance);

    // Analysis Model - Essential (macros only)
    _analysisModelEssential = vertexAI.generativeModel(
      model: analysisModelName,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_essentialNutrition,
      ),
      systemInstruction: Content.text(RemoteConfigService.essentialPrompt),
    );

    // Analysis Model - Comprehensive (macros + vitamins/minerals)
    _analysisModelComprehensive = vertexAI.generativeModel(
      model: analysisModelName,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_comprehensiveNutrition,
      ),
      systemInstruction: Content.text(RemoteConfigService.comprehensivePrompt),
    );

    // Search Model with Google Search (no schema - controlled generation not supported)
    _searchModel = vertexAI.generativeModel(
      model: searchModelName,
      tools: [Tool.googleSearch()],
      systemInstruction: Content.text(RemoteConfigService.searchPrompt),
    );

    // Evaluation Model (health evaluation)
    _evaluationModel = vertexAI.generativeModel(
      model: evaluationModelName,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_aievaluation,
      ),
      systemInstruction: Content.text(RemoteConfigService.daySummaryPrompt),
    );

    // Progress Evaluation Model (20-day progress with Google Search)
    _progressEvaluationModel = vertexAI.generativeModel(
      model: evaluationModelName,
      tools: [Tool.googleSearch()],
      systemInstruction: Content.text(
        'You are a nutrition and fitness expert evaluating a user\'s 20-day nutrition progress. '
        'Use Google Search to look up the latest science-based nutrition recommendations when needed. '
        'Provide evidence-based, actionable feedback.',
      ),
    );

    _isInitialized = true;
  }

  // ============================================
  // IMAGE ANALYSIS (single or multiple images)
  // ============================================

  /// Analyze food image(s) - handles single or multiple images
  /// [includeVitamins] - if true, returns comprehensive data with vitamins/minerals
  ///
  /// For multiple images: each image is treated as ONE ingredient,
  /// all combined into a single dish.
  static Future<String?> analyzeImages(
    List<Uint8List> imageBytesList, {
    bool includeVitamins = false,
    String? additionalPrompt,
  }) async {
    final model = includeVitamins
        ? _analysisModelComprehensive
        : _analysisModelEssential;

    if (model == null) {
      throw Exception('Analysis model not initialized.');
    }

    if (imageBytesList.isEmpty) {
      throw Exception('No images provided.');
    }

    // Build the prompt - add multi-image context only when needed
    String prompt;
    if (additionalPrompt != null) {
      prompt = additionalPrompt;
    } else if (imageBytesList.length == 1) {
      prompt = "Analyze this food image and identify all ingredients with their nutritional values.";
    } else {
      prompt = RemoteConfigService.multiImageAddition +
          "Analyze these ${imageBytesList.length} food images. Each image represents ONE ingredient. Combine them into a single dish.";
    }

    // Build content with all images
    final parts = <Part>[TextPart(prompt)];
    for (final imageBytes in imageBytesList) {
      parts.add(InlineDataPart('image/jpeg', imageBytes));
    }

    final content = [Content.multi(parts)];
    final response = await model.generateContent(content);
    return response.text;
  }

  /// Convenience method for single image analysis
  static Future<String?> analyzeImage(
    Uint8List imageBytes, {
    bool includeVitamins = false,
    String? additionalPrompt,
  }) async {
    return analyzeImages(
      [imageBytes],
      includeVitamins: includeVitamins,
      additionalPrompt: additionalPrompt,
    );
  }

  // ============================================
  // INGREDIENT SEARCH (with Google Search)
  // ============================================

  /// Search for ingredient nutritional information using Google Search
  /// Returns comprehensive nutritional data as structured JSON matching the analysis schema.
  ///
  /// [searchText] - User's search input (e.g. "chicken breast", "200g rice", "1 cup oatmeal").
  /// The model infers quantities from the text.
  static Future<String?> searchIngredient(String searchText) async {
    if (_searchModel == null) {
      throw Exception('Search model not initialized.');
    }

    final searchPrompt = "Look up the complete nutritional information for: $searchText\n\n";

    final searchContent = [Content.text(searchPrompt)];
    final searchResponse = await _searchModel!.generateContent(searchContent);
    final rawNutritionText = searchResponse.text;

    debugPrint('=== [searchIngredient] Step 1: Raw model response ===');
    debugPrint(rawNutritionText ?? '(null)');
    debugPrint('=== [searchIngredient] End Step 1 ===');

    if (rawNutritionText == null || rawNutritionText.trim().isEmpty) {
      return null;
    }

    return _extractAndFormatNutritionJson(rawNutritionText, searchText);
  }

  /// Extracts JSON from model response (handles ```json, extra text) and formats to schema.
  static String? _extractAndFormatNutritionJson(String rawText, String searchText) {
    debugPrint('=== [searchIngredient] Step 2: Extract JSON from response ===');
    final jsonStr = _extractJsonFromResponse(rawText);
    if (jsonStr == null) {
      debugPrint('Failed to extract JSON from response');
      return null;
    }
    debugPrint('Extracted JSON string:\n$jsonStr');
    debugPrint('=== [searchIngredient] End Step 2 ===');

    try {
      debugPrint('=== [searchIngredient] Step 3: Parse and format to schema ===');
      final decoded = jsonDecode(jsonStr);

      // Handle both JSON objects and arrays
      Map<String, dynamic>? parsed;
      List<Map<String, dynamic>>? parsedList;

      if (decoded is Map<String, dynamic>) {
        parsed = decoded;
      } else if (decoded is List && decoded.isNotEmpty) {
        // Array of ingredients — wrap into ingredients list
        parsedList = decoded
            .whereType<Map<String, dynamic>>()
            .toList();
      }

      if (parsed == null && (parsedList == null || parsedList.isEmpty)) {
        debugPrint('Parsed result is null or empty');
        return null;
      }

      final Map<String, dynamic> formatted;
      if (parsedList != null) {
        // Model returned an array — normalize each item as an ingredient
        final ingredients = parsedList
            .map((item) => _normalizeIngredient(_flattenMap(_lowercaseKeys(item)), searchText))
            .toList();
        formatted = {
          'image_classification': 'food',
          'ingredients': ingredients,
          'dishName': searchText,
          'confidence': 1.0,
          'analysisNotes': '',
          'aiEvaluation': '',
          'isHighlyProcessed': false,
        };
        debugPrint('Formatted ${ingredients.length} ingredients from array');
      } else {
        debugPrint('Parsed object keys: ${parsed!.keys.toList()}');
        formatted = _formatToComprehensiveSchema(_flattenMap(_lowercaseKeys(parsed)), searchText);
      }

      final result = jsonEncode(formatted);
      debugPrint('Formatted result:\n$result');
      debugPrint('=== [searchIngredient] End Step 3 ===');

      return result;
    } catch (e) {
      debugPrint('Parse/format failed: $e');
      return null;
    }
  }

  /// Extracts JSON from text that may contain markdown code fences or extra prose.
  static String? _extractJsonFromResponse(String text) {
    final trimmed = text.trim();

    // 1. Try code fence: ```json ... ``` or ``` ... ```
    final codeFence = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)\n?```');
    final fenceMatch = codeFence.firstMatch(trimmed);
    if (fenceMatch != null) {
      final extracted = fenceMatch.group(1)?.trim();
      if (extracted != null && extracted.isNotEmpty) {
        debugPrint('  -> Extracted via code fence (```json or ```)');
        return extracted;
      }
    }

    // 2. Try to find JSON object: from first { to last }
    final braceMatch = RegExp(r'\{[\s\S]*\}').firstMatch(trimmed);
    if (braceMatch != null) {
      debugPrint('  -> Extracted via brace match {...}');
      return braceMatch.group(0);
    }

    debugPrint('  -> No JSON found');
    return null;
  }

  /// Converts parsed model output to comprehensive schema format.
  /// Expects keys already lowercased via _lowercaseKeys.
  static Map<String, dynamic> _formatToComprehensiveSchema(Map<String, dynamic> parsed, String searchText) {
    // Model may return flat object or already have ingredients array
    List<Map<String, dynamic>> ingredientsList = [];
    if (parsed['ingredients'] is List) {
      for (final item in parsed['ingredients'] as List) {
        if (item is Map<String, dynamic>) {
          ingredientsList.add(_normalizeIngredient(_flattenMap(_lowercaseKeys(item)), searchText));
        }
      }
    }
    // If no ingredients array, treat the whole object as a single flat ingredient
    if (ingredientsList.isEmpty) {
      ingredientsList.add(_normalizeIngredient(parsed, searchText));
    }

    return {
      'image_classification': parsed['image_classification'] ?? 'food',
      'ingredients': ingredientsList,
      'dishName': parsed['dishname'] ?? parsed['name'] ?? searchText,
      'confidence': _toDouble(parsed['confidence']) ?? 1.0,
      'analysisNotes': parsed['analysisnotes'] ?? '',
      'aiEvaluation': parsed['aievaluation'] ?? parsed['ai_eval'] ?? '',
      'isHighlyProcessed': parsed['ishighlyprocessed'] == true,
    };
  }

  /// Reads a value from the map trying multiple key variants (camelCase and snake_case).
  static double _nutrient(Map<String, dynamic> m, List<String> keys) {
    for (final key in keys) {
      final v = _toDouble(m[key]);
      if (v != null) return v;
    }
    return 0;
  }

  static Map<String, dynamic> _normalizeIngredient(Map<String, dynamic> m, String searchText) {
    return {
      'name': m['name'] ?? m['ingredient'] ?? m['ingedient'] ?? searchText,
      'quantity': m['quantity'] ?? m['serving_size'] ?? '100g',
      'calories': _nutrient(m, ['calories', 'kcal', 'energy']),
      'protein': _nutrient(m, ['protein']),
      'carbs': _nutrient(m, ['carbs', 'carbohydrates', 'total_carbohydrates']),
      'sugar': _nutrient(m, ['sugar', 'sugars', 'total_sugar']),
      'fat': _nutrient(m, ['fat', 'total_fat', 'totalfat']),
      'fiber': _nutrient(m, ['fiber', 'dietary_fiber', 'dietaryfiber']),
      'saturatedFat': _nutrient(m, ['saturatedfat', 'saturated_fat']),
      'unsaturatedFat': _nutrient(m, ['unsaturatedfat', 'unsaturated_fat']),
      'omega3': _nutrient(m, ['omega3', 'omega_3', 'omega-3']),
      'omega6': _nutrient(m, ['omega6', 'omega_6', 'omega-6']),
      'transFat': _nutrient(m, ['transfat', 'trans_fat']),
      'sodium': _nutrient(m, ['sodium']),
      'potassium': _nutrient(m, ['potassium']),
      'calcium': _nutrient(m, ['calcium']),
      'magnesium': _nutrient(m, ['magnesium']),
      'phosphorus': _nutrient(m, ['phosphorus']),
      'iron': _nutrient(m, ['iron']),
      'zinc': _nutrient(m, ['zinc']),
      'selenium': _nutrient(m, ['selenium']),
      'iodine': _nutrient(m, ['iodine']),
      'copper': _nutrient(m, ['copper']),
      'manganese': _nutrient(m, ['manganese']),
      'chromium': _nutrient(m, ['chromium']),
      'vitaminA': _nutrient(m, ['vitamina', 'vitamin_a']),
      'vitaminD': _nutrient(m, ['vitamind', 'vitamin_d']),
      'vitaminE': _nutrient(m, ['vitamine', 'vitamin_e']),
      'vitaminK': _nutrient(m, ['vitamink', 'vitamin_k']),
      'vitaminC': _nutrient(m, ['vitaminc', 'vitamin_c']),
      'thiamin': _nutrient(m, ['thiamin', 'vitamin_b1', 'vitaminb1']),
      'riboflavin': _nutrient(m, ['riboflavin', 'vitamin_b2', 'vitaminb2']),
      'niacin': _nutrient(m, ['niacin', 'vitamin_b3', 'vitaminb3']),
      'pantothenicAcid': _nutrient(m, ['pantothenicacid', 'pantothenic_acid', 'vitamin_b5', 'vitaminb5']),
      'vitaminB6': _nutrient(m, ['vitaminb6', 'vitamin_b6']),
      'biotin': _nutrient(m, ['biotin', 'vitamin_b7', 'vitaminb7']),
      'folate': _nutrient(m, ['folate', 'vitamin_b9', 'vitaminb9', 'folic_acid']),
      'vitaminB12': _nutrient(m, ['vitaminb12', 'vitamin_b12']),
      'choline': _nutrient(m, ['choline']),
      'cholesterol': _nutrient(m, ['cholesterol']),
    };
  }

  /// Lowercases and normalizes all keys in a map so lookups work regardless of casing.
  /// e.g. "Total Fat" → "total_fat", "Serving Size" → "serving_size", "Calories" → "calories"
  static Map<String, dynamic> _lowercaseKeys(Map<String, dynamic> m) {
    return m.map((key, value) {
      final normalized = key.toLowerCase().replaceAll(' ', '_');
      return MapEntry(normalized, value);
    });
  }

  /// Recursively flattens nested sub-objects into a single flat map.
  /// e.g. {"name": "X", "info": {"per_100g": {"calories": 100}}}
  ///   → {"name": "X", "calories": 100}
  /// Non-map values at any level are kept; map values are recursively merged.
  static Map<String, dynamic> _flattenMap(Map<String, dynamic> m) {
    final result = <String, dynamic>{};
    for (final entry in m.entries) {
      if (entry.value is Map<String, dynamic>) {
        // Recursively flatten nested maps and merge into result
        result.addAll(_flattenMap(entry.value as Map<String, dynamic>));
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.trim();
      // Handle N/A, n/a, etc.
      if (s.isEmpty || s.toLowerCase() == 'n/a') return null;
      // Strip unit suffixes like "13.5g", "45.1mg", "2.4mcg", "100kcal"
      final match = RegExp(r'^([\d.]+)').firstMatch(s);
      if (match != null) return double.tryParse(match.group(1)!);
      return double.tryParse(s);
    }
    return null;
  }

  // ============================================
  // AUDIO ANALYSIS (voice description)
  // ============================================

  /// Analyze audio recording describing food
  /// [includeVitamins] - if true, returns comprehensive data with vitamins/minerals
  static Future<String?> analyzeAudio(
    Uint8List audioBytes, {
    bool includeVitamins = false,
  }) async {
    final model = includeVitamins
        ? _analysisModelComprehensive
        : _analysisModelEssential;

    if (model == null) {
      throw Exception('Analysis model not initialized.');
    }

    if (audioBytes.isEmpty) {
      throw Exception('No audio provided.');
    }

    // Build content with audio
    final parts = <Part>[
      TextPart(RemoteConfigService.audioPrompt),
      InlineDataPart('audio/aac', audioBytes),
    ];

    final content = [Content.multi(parts)];
    final response = await model.generateContent(content);
    return response.text;
  }

  // Model getters
  static GenerativeModel? get analysisModelEssential => _analysisModelEssential;
  static GenerativeModel? get analysisModelComprehensive =>
      _analysisModelComprehensive;
  static GenerativeModel? get searchModel => _searchModel;
  static GenerativeModel? get evaluationModel => _evaluationModel;

  // ============================================
  // DAILY HEALTH EVALUATION
  // ============================================

  /// Evaluate daily health based on user profile and nutrition summary
  /// Pre-calculates metrics so the AI doesn't have to do math
  static Future<String?> evaluateDailyHealth({
    required String gender,
    required int age,
    required double weightKg,
    required String goal,
    required double burnedCalories,
    required double totalCalories,
    required double totalProtein,
    required double totalCarbs,
    required double totalFat,
    required double totalFiber,
    required double totalSugar,
    required List<String> meals, // List of meal descriptions with ingredients
    required int totalMealCount,
    required int processedMealCount,
  }) async {
    if (_evaluationModel == null) {
      throw Exception('Evaluation model not initialized.');
    }

    // Pre-calculate values for the AI
    final proteinPerKg = weightKg > 0 ? totalProtein / weightKg : 0.0;
    final netCalories = totalCalories - burnedCalories;
    
    // Gender-specific recommendations
    final maxSugar = gender == 'female' ? 22 : 37;
    final minFiber = gender == 'female' ? 25 : 30;
    final minProteinPerKg = 0.8;

    // Build comprehensive prompt with all data
    final prompt = """
User Profile:
- Gender: $gender
- Age: $age years
- Weight: ${weightKg.toStringAsFixed(1)} kg
- Goal: $goal


Today's Consumption:
- Calories: ${totalCalories.round()} kcal
- Protein: ${totalProtein.toStringAsFixed(1)}g (${proteinPerKg.toStringAsFixed(2)}g per kg body weight - target: ≥${minProteinPerKg}g/kg)
- Carbohydrates: ${totalCarbs.toStringAsFixed(1)}g
- Fat: ${totalFat.toStringAsFixed(1)}g
- Fiber: ${totalFiber.toStringAsFixed(1)}g (min target: ≥${minFiber}g)
- Sugar: ${totalSugar.toStringAsFixed(1)}g (max limit: <${maxSugar}g)

Processed Food Analysis:
- Total meals scanned: $totalMealCount
- Processed meals: $processedMealCount
- Processed food ratio: ${totalMealCount > 0 ? (processedMealCount / totalMealCount * 100).toStringAsFixed(0) : 0}%

Today's Meals:
${meals.map((m) => '- $m').join('\n')}

Provide a brief, direct health evaluation for this day. Only focus on the present information and do not make any predictions or assumptions!
""";

    debugPrint('=== AI Evaluation Prompt ===');
    debugPrint(prompt);
    debugPrint('============================');

    final content = [Content.text(prompt)];
    final response = await _evaluationModel!.generateContent(content);
    return response.text;
  }

  // ============================================
  // 20-DAY PROGRESS EVALUATION
  // ============================================

  /// Evaluate user's 20-day progress based on all meals and goals.
  /// Uses Google Search for latest nutrition science recommendations.
  static Future<String?> evaluateProgress({
    required String gender,
    required int age,
    required double weightKg,
    required String goal,
    required int activeDays,
    required List<Map<String, dynamic>> dailySummaries,
  }) async {
    if (_progressEvaluationModel == null) {
      throw Exception('Progress evaluation model not initialized.');
    }

    final prompt = """
Evaluate this user's 20-day nutrition progress and give detailed, evidence-based feedback.
Use Google Search to verify the latest nutritional science recommendations for this user's profile and goal.

User Profile:
- Gender: $gender
- Age: $age years
- Weight: ${weightKg.toStringAsFixed(1)} kg
- Goal: $goal
- Active tracking days: $activeDays out of 20

Daily Meal Data (last 20 days):
${dailySummaries.map((d) => '${d['date']}: ${d['mealCount']} meals, ${d['calories']} kcal, ${d['protein']}g protein, ${d['carbs']}g carbs, ${d['fat']}g fat, ${d['fiber']}g fiber, ${d['sugar']}g sugar | Meals: ${d['mealDetails']}').join('\n')}

Structure your response with these exact section headers:

SCORE: [a number from 1 to 10]

OVERALL PROGRESS:
[2-3 sentences: Are they on track with their goal?]

STRENGTHS:
[2-3 sentences: What they did well, highlight consistent good habits]

IMPROVEMENTS:
[2-3 sentences: Key areas for improvement, be specific and actionable]

MEAL TIMING:
[1-2 sentences: Feedback on protein distribution across meals, late-night eating, breakfast habits]
""";

    debugPrint('=== 20-Day Progress Evaluation Prompt ===');
    debugPrint(prompt);
    debugPrint('=========================================');

    final content = [Content.text(prompt)];
    final response = await _progressEvaluationModel!.generateContent(content);
    return response.text;
  }
}
