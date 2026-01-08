import 'package:firebase_ai/firebase_ai.dart';
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
You are EdanosAI Food Analyzer. You analyze food pictures. First you check if the picture is a nutritional label or an actual food dish. 

Do one of the following three options depending on the input:

1. In case of a nutritional label extract the nutritional values from the table per 100g! Save this as one single ingredient! 
2. In case of an actual food dish, identify ALL individual ingredients with their nutritional values.
3. In case the input does not depict either a food dish or a nutritional label, examples are random pictures or empty plates etc, then return "No valid input detected".

Your task:
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
  static const String _searchAddition = """

When looking up ingredients:
1. Use Google Search to find accurate, up-to-date nutritional information
2. Provide COMPLETE nutritional values per standard serving (typically 100g unless specified)
3. Be accurate and use reliable nutritional databases
4. If the ingredient is ambiguous (e.g., "chicken"), default to the most common form (e.g., "chicken breast, cooked")
""";

  static const String _audioAddition = """

Listen to this audio recording where the user describes what they ate.
Identify all the food items and ingredients mentioned, estimate reasonable portions,
and provide nutritional information for each.
If the user mentions specific quantities, use those. Otherwise, estimate typical serving sizes.

Your task:
1. Identify ALL ingredients mentioned
2. extract or estimate the quantity of each ingredient (convert to grams/ml)
3. Provide nutritional values for EACH ingredient separately

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

  static String get _searchPrompt =>
      _basePrompt  + _comprehensiveNutrientsAddition + _searchAddition;

  static String get _audioPrompt => _audioAddition;

  /// Initialize the Gemini models.
  /// Firebase must be initialized before calling this.
  static Future<void> initialize() async {
    if (_isInitialized) return;

    // Analysis Model - Essential (macros only)
    _analysisModelEssential = FirebaseAI.vertexAI(location: 'global').generativeModel(
      model: 'gemini-2.5-flash',
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_essentialNutrition,
      ),
      systemInstruction: Content.text(_essentialPrompt),
    );

    // Analysis Model - Comprehensive (macros + vitamins/minerals)
    _analysisModelComprehensive = FirebaseAI.vertexAI(location: 'global').generativeModel(
      model: 'gemini-2.5-flash',
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_comprehensiveNutrition,
      ),
      systemInstruction: Content.text(_comprehensivePrompt),
    );

    // Search Model with Google Search (uses comprehensive schema)
    _searchModel = FirebaseAI.vertexAI(location: 'global').generativeModel(
      model: 'gemini-2.5-flash-lite',
      tools: [Tool.googleSearch()],
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_comprehensiveNutrition,
      ),
      systemInstruction: Content.text(_searchPrompt),
    );

    // Evaluation Model (health evaluation) - using lite model
    _evaluationModel = FirebaseAI.vertexAI(location: 'global').generativeModel(
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
  /// Returns comprehensive nutritional data (macros + vitamins/minerals)
  static Future<String?> searchIngredient(
    String ingredientName, {
    String? quantity,
  }) async {
    if (_searchModel == null) {
      throw Exception('Search model not initialized.');
    }

    final prompt = quantity != null
        ? "Look up the complete nutritional information for $quantity of $ingredientName. Return as a single ingredient in a dish."
        : "Look up the complete nutritional information for $ingredientName (per 100g standard serving). Return as a single ingredient in a dish.";

    final content = [Content.text(prompt)];
    final response = await _searchModel!.generateContent(content);
    return response.text;
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

Today's Meals:
${meals.map((m) => '- $m').join('\n')}

Provide a brief, direct health evaluation for this day. Only focus on the present information and do not make any predictions or assumptions!
""";

    print('=== AI Evaluation Prompt ===');
    print(prompt);
    print('============================');

    final content = [Content.text(prompt)];
    final response = await _evaluationModel!.generateContent(content);
    return response.text;
  }
}
