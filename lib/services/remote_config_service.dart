import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Service for Firebase Remote Config.
/// Allows changing Gemini model names and prompts remotely
/// without releasing a new app version.
class RemoteConfigService {
  static final _rc = FirebaseRemoteConfig.instance;
  static bool _isInitialized = false;

  // Remote Config keys
  static const _kAnalysisModel = 'gemini_analysis_model';
  static const _kSearchModel = 'gemini_search_model';
  static const _kEvaluationModel = 'gemini_evaluation_model';
  static const _kBasePrompt = 'prompt_base';
  static const _kComprehensiveNutrients = 'prompt_comprehensive_nutrients';
  static const _kAiEvaluation = 'prompt_ai_evaluation';
  static const _kMultiImage = 'prompt_multi_image';
  static const _kSearch = 'prompt_search';
  static const _kAudio = 'prompt_audio';
  static const _kDaySummary = 'prompt_day_summary';

  /// Default values — mirrors the current hardcoded values in GeminiService.
  static const Map<String, dynamic> _defaults = {
    _kAnalysisModel: 'gemini-2.5-flash-lite',
    _kSearchModel: 'gemini-2.5-flash-lite',
    _kEvaluationModel: 'gemini-2.5-flash-lite',
    _kBasePrompt: _defaultBasePrompt,
    _kComprehensiveNutrients: _defaultComprehensiveNutrients,
    _kAiEvaluation: _defaultAiEvaluation,
    _kMultiImage: _defaultMultiImage,
    _kSearch: _defaultSearch,
    _kAudio: _defaultAudio,
    _kDaySummary: _defaultDaySummary,
  };

  /// Initialize Remote Config with defaults, then fetch & activate.
  static Future<void> initialize() async {
    if (_isInitialized) return;

    await _rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));

    await _rc.setDefaults(_defaults);

    try {
      await _rc.fetchAndActivate();
      debugPrint('Remote Config fetched and activated.');
    } catch (e) {
      debugPrint('Remote Config fetch failed, using defaults: $e');
    }

    _isInitialized = true;
  }

  // ── Model names ──────────────────────────────────────────

  static String get analysisModel => _rc.getString(_kAnalysisModel);
  static String get searchModel => _rc.getString(_kSearchModel);
  static String get evaluationModel => _rc.getString(_kEvaluationModel);

  // ── Prompts ──────────────────────────────────────────────

  static String get basePrompt => _rc.getString(_kBasePrompt);
  static String get comprehensiveNutrientsAddition =>
      _rc.getString(_kComprehensiveNutrients);
  static String get aiEvaluationPrompt => _rc.getString(_kAiEvaluation);
  static String get multiImageAddition => _rc.getString(_kMultiImage);
  static String get searchPrompt => _rc.getString(_kSearch);
  static String get audioAddition => _rc.getString(_kAudio);
  static String get daySummaryPrompt => _rc.getString(_kDaySummary);

  // Composed prompts (same logic as GeminiService had)
  static String get essentialPrompt => basePrompt + aiEvaluationPrompt;
  static String get comprehensivePrompt =>
      basePrompt + comprehensiveNutrientsAddition + aiEvaluationPrompt;
  static String get audioPrompt => audioAddition;

  // ── Default prompt strings ───────────────────────────────

  static const String _defaultBasePrompt = """
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

  static const String _defaultComprehensiveNutrients = """

- Fatty acids: Omega-3, Omega-6, Trans Fat
- Minerals: Sodium, Potassium, Calcium, Magnesium, Phosphorus, Iron, Zinc, Selenium, Iodine, Copper, Manganese, Chromium
- Vitamins: A, D, E, K, C, B1 (Thiamin), B2 (Riboflavin), B3 (Niacin), B5, B6, B7 (Biotin), B9 (Folate), B12
- Other: Choline, Cholesterol

Convert amounts to appropriate units (g, mg, mcg, IU).
""";

  static const String _defaultAiEvaluation = """
  Provide a brief overall health evaluation for the dish taking all ingredients into account in the field "aiEvaluation".
  For this, consider the following:
  - is the total amount of saturated fat above 5.0g / 100g, this is a risk factor.
  - is the total amount of sodium above 1.5g / 100g
  - is the total amount of sugars above 25g raise a warnig that it contains high amount of sugar!

  Set "isHighlyProcessed" to true if the dish:
  - chemical-based preservatives, emulsifiers like hydrogenated oils, sweeteners like high fructose corn syrup, and artificial colors and flavors.
  - low in nutritional quality and high in saturated fats, added sugars, and sodium (salt)
""";

  static const String _defaultMultiImage = """

IMPORTANT for multiple images:
- Treat each image as a SINGLE INGREDIENT of ONE combined dish
- Combine all images into ONE dish with multiple ingredients
- Name the dish based on the combination of all ingredients
""";

  static const String _defaultSearch = """

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

  static const String _defaultAudio = """

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

  static const String _defaultDaySummary = """
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
- Fiber (min 25g/day for women, 30g/day for men)
- Protein (min 0.8g per kg body weight)
- Overall calorie balance vs their goal

Be concise and actionable. If everything looks good, say so. If there are issues, prioritize the most important one.
""";
}
