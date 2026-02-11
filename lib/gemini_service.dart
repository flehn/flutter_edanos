import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'model_config.dart';
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
  static bool _isInitialized = false;

  // System prompts - Base prompt with modular additions
  static const String _basePrompt = """
You are EdanosAI Food Analyzer. You analyze food pictures. First you classify what type of image this is:

Set "image_classification" to one of:
- "food" - an actual food dish or meal
- "nutritional_label_on_packed_product" - a nutritional label/table on a packaged product
- "packaged_product_only" - the front of a packaged product WITHOUT the nutritional label visible
- "no_food_no_label" - empty plates, random pictures, or anything that is not food-related

Do one of the following depending on the classification:

1. For "nutritional_label_on_packed_product": extract the nutritional values from the table per 100g! Save this as one single ingredient! 
2. For "food": identify ALL individual ingredients with their nutritional values.
3. For "packaged_product_only": identify the product and estimate nutritional values based on typical values for that product type.
4. For "no_food_no_label": return minimal data with no ingredients.

Your task for food analysis:
1. Identify ALL ingredients visible or described
2. Estimate the quantity of each ingredient (convert to grams/ml)
3. Provide nutritional values for EACH ingredient separately

Convert all amounts to grams (g) or milliliters (ml).

For each ingredient, provide:
- Calories (kcal), Protein (g), Carbohydrates (g), Sugar (g)
- Total Fat (g), Saturated Fat (g), Unsaturated Fat (g), Fiber (g)
""";

  // Comprehensive nutrients (vitamins + minerals)
  static const String _comprehensiveNutrientsAddition = """

- Fatty acids: Omega-3, Omega-6, Trans Fat
- Minerals: Sodium, Potassium, Calcium, Magnesium, Phosphorus, Iron, Zinc, Selenium, Iodine, Copper, Manganese, Chromium
- Vitamins: A, D, E, K, C, B1 (Thiamin), B2 (Riboflavin), B3 (Niacin), B5, B6, B7 (Biotin), B9 (Folate), B12
- Other: Choline, Cholesterol

Convert amounts to appropriate units (g, mg, mcg, IU).
""";

// System prompts - Base prompt with modular additions

  static const String _aiEvaluationPrompt = """
  Provide a brief overall health evaluation for the dish taking all ingredients into account in the field "aiEvaluation".
  For this, consider the following:
  - is the total amount of saturated fat above 5.0g / 100g, this is a risk factor. 
  - is the total amount of sodium above 1.5g / 100g
  - is the total amount of sugars above 25g raise a warnig that it contains high amount of sugar! 

  Set "isHighlyProcessed" to true if the dish:
  - chemical-based preservatives, emulsifiers like hydrogenated oils, sweeteners like high fructose corn syrup, and artificial colors and flavors.
  - low in nutritional quality and high in saturated fats, added sugars, and sodium (salt)
""";

  // Addition for multiple images
  static const String _multiImageAddition = """

IMPORTANT for multiple images:
- Treat each image as a SINGLE INGREDIENT of ONE combined dish
- Combine all images into ONE dish with multiple ingredients
- Name the dish based on the combination of all ingredients
""";


  // Search-specific addition
  static const String _searchPrompt = """

You are a nutrition expert providing nutritional information for a given ingredient.
1. Use Google Search to find accurate, up-to-date nutritional information
2. Provide COMPLETE nutritional values per standard serving (typically 100g unless specified)
3. Be accurate and use reliable nutritional databases
4. If the ingredient is ambiguous (e.g., "chicken"), default to the most common form (e.g., "chicken breast, cooked")

Always return the nutritional information in the following JSON format and return nothing else:
For each ingredient, provide the values per 100g if not specified otherwise:
- Calories (kcal), 
- Protein (g), 
- Carbohydrates (g), 
- Sugar (g)
- Total Fat (g), 
- Saturated Fat (g), 
- Unsaturated Fat (g), 
- Fiber (g)
Return only the JSON format and nothing else!
""";

  static const String _audioAddition = """

Listen to this audio recording. First, determine if the user is describing food or something else.

Set "image_classification" to one of:
- "food" - the user is describing a food dish, meal, or ingredient
- "no_food_no_label" - the user is NOT describing food (random speech, unrelated topic, etc.)

If "no_food_no_label": return minimal data with no ingredients.

If "food": identify ALL food items and ingredients mentioned.
- Extract or estimate the quantity of each ingredient (convert to grams/ml)
- Provide nutritional values for EACH ingredient separately
- If the user mentions specific quantities, use those. Otherwise, estimate typical serving sizes.

Convert all amounts to grams (g) or milliliters (ml).

For each ingredient, provide:
- Calories (kcal), Protein (g), Carbohydrates (g), Sugar (g)
- Total Fat (g), Saturated Fat (g), Unsaturated Fat (g), Fiber (g)
""";

  // AI Evaluation prompt for daily health summary
  static const String _aiEvaluationPrompt_daysummarie = """
You are a nutrition expert providing brief health evaluations.
Based on the user's profile and daily consumption data provided, evaluate their nutrition.

For "good": Describe what they did well today (1-2 sentences, be encouraging).
For "critical": Describe any health concerns or areas for improvement (1-2 sentences, be constructive).
For "processedFoodFeedback": Evaluate the processed food consumption based on the counts provided.
  - If 0 processed foods were scanned: give an encouraging compliment (e.g. "Great job avoiding processed foods today!")
  - If more than 50% of scanned items were processed: give a constructive warning about relying on processed foods
  - Otherwise: give a brief neutral or mildly encouraging note

Focus on:
- total sugar intake (max 22g/day for women, 37g/day for men)
- Saturated fat (max 10% of total calories)
- Fiber (min 25g/day for women, 30g/day for men)  
- Protein (min 0.8g per kg body weight)
- Overall calorie balance vs their goal

Be concise and actionable. If everything looks good, say so. If there are issues, prioritize the most important one.
""";


  // Composed prompts (multi-image addition is added dynamically in analyzeImages)
  static String get _essentialPrompt =>
      _basePrompt + _aiEvaluationPrompt;

  static String get _comprehensivePrompt =>
      _basePrompt + _comprehensiveNutrientsAddition + _aiEvaluationPrompt;


  static String get _audioPrompt => _audioAddition;

  /// Initialize the Gemini models.
  /// Firebase must be initialized before calling this.
  static Future<void> initialize() async {
    if (_isInitialized) return;

    // Analysis Model - Essential (macros only)
    _analysisModelEssential = FirebaseAI.vertexAI(location: 'europe-west1', appCheck: FirebaseAppCheck.instance).generativeModel(
      model: 'gemini-2.5-flash-lite',
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_essentialNutrition,
      ),
      systemInstruction: Content.text(_essentialPrompt),
    );

    // Analysis Model - Comprehensive (macros + vitamins/minerals)
    _analysisModelComprehensive = FirebaseAI.vertexAI(location: 'europe-west1', appCheck: FirebaseAppCheck.instance).generativeModel(
      model: 'gemini-2.5-flash-lite',
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_comprehensiveNutrition,
      ),
      systemInstruction: Content.text(_comprehensivePrompt),
    );

    // Search Model with Google Search (no schema - controlled generation not supported)
    _searchModel = FirebaseAI.vertexAI(location: 'europe-west1', appCheck: FirebaseAppCheck.instance).generativeModel(
      model: 'gemini-2.5-flash-lite',
      tools: [Tool.googleSearch()],
      systemInstruction: Content.text(_searchPrompt),
    );


    // Evaluation Model (health evaluation) - using lite model
    _evaluationModel = FirebaseAI.vertexAI(location: 'europe-west1', appCheck: FirebaseAppCheck.instance).generativeModel(
      model: 'gemini-2.5-flash-lite',
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_aievaluation,
      ),
      systemInstruction: Content.text(_aiEvaluationPrompt_daysummarie),
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
      prompt = _multiImageAddition +
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
      TextPart(_audioPrompt),
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
    required double totalSaturatedFat,
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
    final saturatedFatCalories = totalSaturatedFat * 9; // 9 kcal per gram of fat
    final saturatedFatPercent = totalCalories > 0
        ? (saturatedFatCalories / totalCalories * 100)
        : 0.0;
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
- Saturated Fat: ${totalSaturatedFat.toStringAsFixed(1)}g (${saturatedFatPercent.toStringAsFixed(1)}% of calories - limit: <10%)
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
}
