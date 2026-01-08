import 'package:firebase_ai/firebase_ai.dart';

// By default, for Firebase AI Logic SDKs, all fields are considered required
// unless you specify them as optional in an optionalProperties array.

// ============================================
// ESSENTIAL NUTRITION SCHEMA (macros only)
// ============================================

final jsonSchema_essentialNutrition = Schema.object(
  properties: {
    'is_food': Schema.boolean(
      description: 'Whether the image contains food. Be critical - it must be real food or food products!',
    ),
    'ingredients': Schema.array(
      items: Schema.object(
        properties: {
          'name': Schema.string(),
          'quantity': Schema.string(), // e.g., "75g" or "30 ml"
          // Essential Macronutrients
          'calories': Schema.number(), // kcal
          'protein': Schema.number(), // g
          'carbs': Schema.number(), // g
          'sugar': Schema.number(), // g
          'fat': Schema.number(), // g
          'fiber': Schema.number(), // g
          'saturatedFat': Schema.number(), // g
          'unsaturatedFat': Schema.number(), // g
        },
      ),
    ),
    'dishName': Schema.string(),
    'confidence': Schema.number(),
    'analysisNotes': Schema.string(),
    'aiEvaluation': Schema.string(
      description:
          'Brief AI evaluation (1-2 sentences) about overall healthiness and suggestions',
    ),
    'isHighlyProcessed': Schema.boolean(
      description:
          'True if the meal is highly processed (packaged/ultra-processed), false otherwise',
    ),
  },
);

// ============================================
// COMPREHENSIVE NUTRITION SCHEMA (macros + vitamins/minerals)
// ============================================

final jsonSchema_comprehensiveNutrition = Schema.object(
  properties: {
    'is_food': Schema.boolean(
      description: 'Whether the image contains food. Be critical - it must be real food or food products!',
    ),
    'ingredients': Schema.array(
      items: Schema.object(
        properties: {
          'name': Schema.string(),
          'quantity': Schema.string(),
          // Essential Macronutrients
          'calories': Schema.number(), // kcal
          'protein': Schema.number(), // g
          'carbs': Schema.number(), // g
          'sugar': Schema.number(), // g
          'fat': Schema.number(), // g
          'fiber': Schema.number(), // g
          'saturatedFat': Schema.number(), // g
          'unsaturatedFat': Schema.number(), // g
          // Essential Fatty Acids
          'omega3': Schema.number(), // g
          'omega6': Schema.number(), // g
          'transFat': Schema.number(), // g
          // Major Minerals
          'sodium': Schema.number(), // mg
          'potassium': Schema.number(), // mg
          'calcium': Schema.number(), // mg
          'magnesium': Schema.number(), // mg
          'phosphorus': Schema.number(), // mg
          // Essential Trace Minerals
          'iron': Schema.number(), // mg
          'zinc': Schema.number(), // mg
          'selenium': Schema.number(), // mcg
          'iodine': Schema.number(), // mcg
          'copper': Schema.number(), // mcg
          'manganese': Schema.number(), // mg
          'chromium': Schema.number(), // mcg
          // Fat-Soluble Vitamins
          'vitaminA': Schema.number(), // mcg RAE
          'vitaminD': Schema.number(), // IU
          'vitaminE': Schema.number(), // mg
          'vitaminK': Schema.number(), // mcg
          // Water-Soluble Vitamins
          'vitaminC': Schema.number(), // mg
          'thiamin': Schema.number(), // B1, mg
          'riboflavin': Schema.number(), // B2, mg
          'niacin': Schema.number(), // B3, mg
          'pantothenicAcid': Schema.number(), // B5, mg
          'vitaminB6': Schema.number(), // mg
          'biotin': Schema.number(), // B7, mcg
          'folate': Schema.number(), // B9, mcg
          'vitaminB12': Schema.number(), // mcg
          // Other Important Nutrients
          'choline': Schema.number(), // mg
          'cholesterol': Schema.number(), // mg
        },
      ),
    ),
    'dishName': Schema.string(),
    'confidence': Schema.number(),
    'analysisNotes': Schema.string(),
    'aiEvaluation': Schema.string(
      description:
          'Brief AI evaluation (1-2 sentences) about overall healthiness and suggestions',
    ),
    'isHighlyProcessed': Schema.boolean(
      description:
          'True if the meal is highly processed (packaged/ultra-processed), false otherwise',
    ),
  },
);
