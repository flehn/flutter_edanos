import 'package:firebase_ai/firebase_ai.dart';

// By default, for Firebase AI Logic SDKs, all fields are considered required
// unless you specify them as optional in an optionalProperties array.

// ============================================
// ESSENTIAL NUTRITION SCHEMA (macros only)
// ============================================

final jsonSchema_essentialNutrition = Schema.object(
  properties: {
    'image_classification': Schema.enumString(
      enumValues: ['food', 'nutritional_label_on_packed_product', 'packaged_product_only', 'no_food_no_label'],
      description: 'Classify the image: "food" for food dishes, "nutritional_label_on_packed_product" for nutrition labels, "packaged_product_only" for packaged product fronts without labels, or "no_food_no_label" for empty plates, random images, etc.',
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
    'image_classification': Schema.enumString(
      enumValues: ['food', 'nutritional_label_on_packed_product', 'packaged_product_only', 'no_food_no_label'],
      description: 'Classify the image: "food" for food dishes, "nutritional_label_on_packed_product" for nutrition labels, "packaged_product_only" for packaged product fronts without labels, or "no_food_no_label" for empty plates, random images, etc.',
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

// ============================================
// AI EVALUATION SCHEMA ()
// ============================================

final jsonSchema_aievaluation = Schema.object(
  properties: {
    'good': Schema.string(
      description:
          'Describe the health benefits of the meal!',
    ),
    'critical': Schema.string(
      description:
          'Describe the potential health issues!',
    ),
    'processedFoodFeedback': Schema.string(
      description:
          'Feedback about processed food consumption: compliment if none, warning if majority (>50%) were processed.',
    ),
  },
);

// ============================================
// 20-DAY PROGRESS EVALUATION SCHEMA
// ============================================

final jsonSchema_progressEvaluation = Schema.object(
  properties: {
    'overallProgress': Schema.string(
      description:
          'Overall assessment of the user\'s 20-day nutrition journey (2-3 sentences). Are they on track with their goal (gain/lose weight)?',
    ),
    'strengths': Schema.string(
      description:
          'What the user did well over the 20-day period (2-3 sentences). Highlight consistent good habits.',
    ),
    'improvements': Schema.string(
      description:
          'Key areas for improvement over the next 20 days (2-3 sentences). Be specific and actionable.',
    ),
    'mealTimingFeedback': Schema.string(
      description:
          'Feedback on meal timing patterns: protein distribution across meals, late-night eating, breakfast habits (1-2 sentences).',
    ),
    'progressScore': Schema.number(
      description:
          'A score from 1-10 reflecting overall progress towards the user\'s goal.',
    ),
  },
);