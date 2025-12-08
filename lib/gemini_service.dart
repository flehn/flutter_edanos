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
class GeminiService {
  static GenerativeModel? _analysisModelEssential;
  static GenerativeModel? _analysisModelComprehensive;
  static GenerativeModel? _searchModel;
  static bool _isInitialized = false;

  // System prompts
  static const String _essentialPrompt = """
You are EdanosAI Food Analyzer. You analyze food images and identify ALL individual ingredients with their nutritional values.

Your task:
1. Identify ALL ingredients visible in the food image(s)
2. Estimate the quantity of each ingredient (convert to grams/ml)
3. Provide essential nutritional values for EACH ingredient separately

IMPORTANT for multiple images:
- Treat each image as a SINGLE INGREDIENT of ONE combined dish
- Combine all images into ONE dish with multiple ingredients
- Name the dish based on the combination of all ingredients

For each ingredient, provide:
- Calories (kcal), Protein (g), Carbohydrates (g), Sugar (g)
- Total Fat (g), Saturated Fat (g), Unsaturated Fat (g), Fiber (g)

Convert all amounts to grams (g) or milliliters (ml).
If an image shows a packaged food product with a Nutritional Information Panel, use that information.
""";

  static const String _comprehensivePrompt = """
You are EdanosAI Food Analyzer. You analyze food images and identify ALL individual ingredients with COMPLETE nutritional profiles including vitamins and minerals.

Your task:
1. Identify ALL ingredients visible in the food image(s)
2. Estimate the quantity of each ingredient (convert to grams/ml)
3. Provide COMPREHENSIVE nutritional values for EACH ingredient including all vitamins and minerals

IMPORTANT for multiple images:
- Treat each image as a SINGLE INGREDIENT of ONE combined dish
- Combine all images into ONE dish with multiple ingredients
- Name the dish based on the combination of all ingredients

For each ingredient, provide ALL values:
- Macros: Calories, Protein, Carbs, Sugar, Fat, Fiber, Saturated/Unsaturated Fat
- Fatty acids: Omega-3, Omega-6, Trans Fat
- Minerals: Sodium, Potassium, Calcium, Magnesium, Phosphorus, Iron, Zinc, Selenium, Iodine, Copper, Manganese, Chromium
- Vitamins: A, D, E, K, C, B1 (Thiamin), B2 (Riboflavin), B3 (Niacin), B5, B6, B7 (Biotin), B9 (Folate), B12
- Other: Choline, Cholesterol

Convert amounts to appropriate units (g, mg, mcg, IU).
If an image shows a packaged food product with a Nutritional Information Panel, use that information.
""";

  static const String _searchPrompt = """
You are EdanosAI Ingredient Search. You help users quickly look up nutritional information for any ingredient or food item.

When a user searches for an ingredient:
1. Use Google Search to find accurate, up-to-date nutritional information
2. Provide COMPLETE nutritional values per standard serving (typically 100g unless specified)
3. Include ALL macros, vitamins, and minerals

Return comprehensive data including:
- Macros: Calories, Protein, Carbs, Sugar, Fat, Fiber, Saturated/Unsaturated Fat
- Fatty acids: Omega-3, Omega-6, Trans Fat
- Minerals: Sodium, Potassium, Calcium, Magnesium, Phosphorus, Iron, Zinc, Selenium, Iodine, Copper, Manganese, Chromium
- Vitamins: A, D, E, K, C, B1, B2, B3, B5, B6, B7, B9, B12
- Other: Choline, Cholesterol

Be accurate and use reliable nutritional databases. If the ingredient is ambiguous (e.g., "chicken"), default to the most common form (e.g., "chicken breast, cooked").

Always provide values per 100g unless the user specifies a different quantity.
""";

  /// Initialize the Gemini models.
  /// Firebase must be initialized before calling this.
  static Future<void> initialize() async {
    if (_isInitialized) return;

    // Analysis Model - Essential (macros only)
    _analysisModelEssential = FirebaseAI.vertexAI().generativeModel(
      model: 'gemini-2.5-flash',
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_essentialNutrition,
      ),
      systemInstruction: Content.text(_essentialPrompt),
    );

    // Analysis Model - Comprehensive (macros + vitamins/minerals)
    _analysisModelComprehensive = FirebaseAI.vertexAI().generativeModel(
      model: 'gemini-2.5-flash',
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_comprehensiveNutrition,
      ),
      systemInstruction: Content.text(_comprehensivePrompt),
    );

    // Search Model with Google Search (uses comprehensive schema)
    _searchModel = FirebaseAI.vertexAI().generativeModel(
      model: 'gemini-2.5-flash-lite',
      tools: [Tool.googleSearch()],
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: jsonSchema_comprehensiveNutrition,
      ),
      systemInstruction: Content.text(_searchPrompt),
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

    final prompt =
        additionalPrompt ??
        (imageBytesList.length == 1
            ? "Analyze this food image and identify all ingredients with their nutritional values."
            : "Analyze these ${imageBytesList.length} food images. Each image represents ONE ingredient. Combine them into a single dish.");

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
  /// Uses the essential model to analyze spoken food descriptions
  static Future<String?> analyzeAudio(Uint8List audioBytes) async {
    final model = _analysisModelEssential;

    if (model == null) {
      throw Exception('Analysis model not initialized.');
    }

    if (audioBytes.isEmpty) {
      throw Exception('No audio provided.');
    }

    const prompt = '''
Listen to this audio recording where the user describes what they ate.
Identify all the food items and ingredients mentioned, estimate reasonable portions,
and provide nutritional information for each.
If the user mentions specific quantities, use those. Otherwise, estimate typical serving sizes.
''';

    // Build content with audio
    final parts = <Part>[
      TextPart(prompt),
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
}
