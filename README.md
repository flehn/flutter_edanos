# Edanos - AI Food Analyzer

Edanos is a cross-platform Flutter application that uses Google's Gemini AI to analyze food images, extract detailed nutritional information, and help users track their daily nutrition intake.

## Features

- **AI-Powered Food Scanning** - Take a photo of your meal and get instant nutritional breakdown
- **Nutritional Label Reading** - Point the camera at a nutrition label for accurate data extraction
- **Voice Meal Descriptions** - Describe your meal via audio recording for hands-free logging
- **Ingredient Search** - Look up individual ingredients with Google Search-powered accuracy
- **Daily Health Evaluations** - AI-generated daily feedback on your eating habits
- **Quick-Add Foods** - Save frequent meals for one-tap logging
- **Health App Sync** - Integration with Apple Health and Health Connect
- **Macro and Micronutrient Tracking** - Track 40+ nutrients from basic macros to vitamins and minerals

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                   Flutter App                    │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  Screens  │→│  Services │→│    Models      │  │
│  │  (UI)     │  │ (Logic)  │  │ (Data)        │  │
│  └──────────┘  └──────────┘  └───────────────┘  │
│                      │                           │
└──────────────────────┼───────────────────────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
   ┌────────────┐ ┌─────────┐ ┌──────────┐
   │  Firebase   │ │ Firebase│ │ Firebase │
   │  Firestore  │ │ Storage │ │ AI       │
   │  (data)     │ │ (images)│ │ (Gemini) │
   └────────────┘ └─────────┘ └──────────┘
```

## Firebase Information Flow

Edanos uses Firebase as its backend with the following services:

### Services Used

| Service | Purpose |
|---------|---------|
| **Firebase Authentication** | User identity (anonymous + email/password hybrid) |
| **Cloud Firestore** | Primary NoSQL database for all structured data |
| **Firebase Storage** | Image storage for meal photos |
| **Firebase App Check** | Security enforcement (Play Integrity / App Attest) |
| **Firebase AI (Vertex AI)** | Gemini model access from the client via `europe-west1` |

### Data Flow: Image to Database

The core flow from capturing a meal to persisting it:

```
1. User captures image (camera/gallery)
         │
         ▼
2. GeminiService.analyzeImage()
   Sends image to Gemini 2.5 Flash-Lite
   Receives structured JSON with ingredients + nutrients
         │
         ▼
3. Meal.fromGeminiJson()
   Parses AI response into Meal and Ingredient objects
         │
         ▼
4. MealDetailScreen
   User reviews and adjusts ingredient amounts/names
         │
         ▼
5. MealRepository.saveMeal()
   ├──→ StorageService.storeImage()  → Firebase Storage (returns imageUrl)
   └──→ FirestoreService.saveMeal()  → Firestore document
         │
         ▼
6. Data available for daily/weekly summaries and evaluations
```

### Firestore Database Structure

All data is scoped per user. Security rules enforce that each user can only access their own documents.

```
firestore
└── users/{userId}
    │
    ├── meals/{mealId}
    │   ├── id: String
    │   ├── name: String                    # Dish name (e.g. "Chicken Stir Fry")
    │   ├── scannedAt: String               # ISO 8601 timestamp
    │   ├── imageUrl: String                # Firebase Storage download URL
    │   ├── confidence: Number              # AI confidence score (0-1)
    │   ├── analysisNotes: String           # AI notes about the analysis
    │   ├── aiEvaluation: String            # Healthiness evaluation
    │   ├── isHighlyProcessed: Boolean      # Ultra-processed food flag
    │   ├── imageClassification: String     # "food" | "nutritional_label_on_packed_product" | "packaged_product_only"
    │   ├── totalCalories: Number           # Pre-computed sum across ingredients
    │   ├── totalProtein: Number
    │   ├── totalCarbs: Number
    │   ├── totalFat: Number
    │   └── ingredients: Array
    │       └── [each ingredient]
    │           ├── id, name, amount, originalAmount, unit
    │           ├── originalCalories, originalProtein, originalCarbs, originalFat
    │           ├── originalFiber, originalSugar, originalSaturatedFat, originalUnsaturatedFat
    │           └── (optional comprehensive: vitamins, minerals, fatty acids)
    │
    ├── settings/
    │   ├── goals/{document}
    │   │   ├── dailyCalories, dailyProtein, dailyCarbs, dailyFat, dailyFiber
    │   │   ├── isGainMode: Boolean
    │   │   └── perMealProtein, perMealCarbs, perMealFat
    │   │
    │   └── preferences/{document}
    │       ├── useDetailedAnalysis: Boolean     # Enables comprehensive nutrient tracking
    │       ├── syncToHealth: Boolean            # Apple Health / Health Connect sync
    │       ├── units: String                    # "Metric" | "Imperial"
    │       ├── notificationsEnabled, mealRemindersEnabled
    │       ├── reminderTimesMinutes: Array<Number>
    │       └── gender, age, weight              # Used for daily evaluations
    │
    ├── quickAdd/{itemId}
    │   ├── id, name, calories, protein, carbs, fat
    │   ├── usageCount: Number                  # Tracks frequency for sorting
    │   └── imageUrl: String (optional)
    │
    └── evaluations/{yyyy-MM-dd}
        ├── date: String
        ├── good: String                        # What went well
        ├── critical: String                    # Health concerns
        └── processedFoodFeedback: String       # Processed food consumption feedback
```

**Indexing:** Firestore composite indexes are configured on the `scannedAt` field (ascending and descending) for efficient date-range queries on the meals collection.

## Gemini AI Models

Edanos uses Google's Gemini models via the Firebase AI SDK (Vertex AI backend, region `europe-west1`).

### Model: `gemini-2.5-flash-lite`

All AI features use **Gemini 2.5 Flash-Lite**, a fast and cost-efficient model optimized for structured output. It is used in four distinct configurations:

#### 1. Food Image Analysis (Essential)

Analyzes food images and returns macronutrient data. The AI first classifies the image into one of four categories:

- `"food"` - A dish or meal (AI estimates ingredients and portions)
- `"nutritional_label_on_packed_product"` - A nutrition label (AI extracts per-100g values)
- `"packaged_product_only"` - A product front without visible label (AI estimates based on product type)
- `"no_food_no_label"` - Not food (rejected with `NotFoodException`)

Supports multi-image input (1-10 images), where each image is treated as one ingredient combined into a single dish.

**Response schema:** dish name, confidence, ingredients with macros (calories, protein, carbs, fat, fiber, sugar, saturated/unsaturated fat), AI evaluation, and processed food flag.

#### 2. Food Image Analysis (Comprehensive)

Same as above, but with the `useDetailedAnalysis` preference enabled. Extends the schema to include 40+ nutrients: all essential macros plus fatty acids, major minerals, trace minerals, fat-soluble vitamins, water-soluble vitamins, and other nutrients like choline and cholesterol.

#### 3. Ingredient Search

Uses `Tool.googleSearch()` to look up nutritional data for individual ingredients by name. This leverages real-time Google Search results for accurate, up-to-date nutritional information rather than relying solely on the model's training data.

#### 4. Daily Health Evaluation

Receives the user's aggregated daily intake (total macros, number of meals, processed food count) along with user profile data (gender, age, weight) and nutritional goals. Returns structured feedback with three fields: what went well, health concerns, and processed food consumption feedback.

## Nutritional Data Model

Edanos tracks nutrition at the **ingredient level**. Each ingredient stores its own nutritional values, and meal totals are computed as the sum of all ingredients.

### Scaling System

Each ingredient stores both `originalAmount` (as returned by Gemini) and `amount` (as adjusted by the user). All nutritional values scale proportionally:

```
scaleFactor = amount / originalAmount
displayedCalories = originalCalories * scaleFactor
```

For example, if Gemini estimates "100g chicken breast = 165 kcal" and the user changes the amount to 150g, the displayed calories become `165 * 1.5 = 247.5 kcal`. This applies to every tracked nutrient.

Adjusting one ingredient does **not** affect other ingredients in the same meal.

### Essential Nutrients (Always Tracked)

| Nutrient | Unit | Field |
|----------|------|-------|
| Calories | kcal | `calories` |
| Protein | g | `protein` |
| Carbohydrates | g | `carbs` |
| Sugar | g | `sugar` |
| Fat | g | `fat` |
| Fiber | g | `fiber` |
| Saturated Fat | g | `saturatedFat` |
| Unsaturated Fat | g | `unsaturatedFat` |

### Comprehensive Nutrients (Optional, Enabled via Settings)

When `useDetailedAnalysis` is enabled, the following are also tracked per ingredient:

**Fatty Acids:**

| Nutrient | Unit |
|----------|------|
| Omega-3 | g |
| Omega-6 | g |
| Trans Fat | g |

**Major Minerals:**

| Nutrient | Unit |
|----------|------|
| Sodium | mg |
| Potassium | mg |
| Calcium | mg |
| Magnesium | mg |
| Phosphorus | mg |

**Trace Minerals:**

| Nutrient | Unit |
|----------|------|
| Iron | mg |
| Zinc | mg |
| Selenium | mcg |
| Iodine | mcg |
| Copper | mcg |
| Manganese | mg |
| Chromium | mcg |

**Fat-Soluble Vitamins:**

| Nutrient | Unit |
|----------|------|
| Vitamin A | mcg RAE |
| Vitamin D | IU |
| Vitamin E | mg |
| Vitamin K | mcg |

**Water-Soluble Vitamins:**

| Nutrient | Unit |
|----------|------|
| Vitamin C | mg |
| Thiamin (B1) | mg |
| Riboflavin (B2) | mg |
| Niacin (B3) | mg |
| Pantothenic Acid (B5) | mg |
| Vitamin B6 | mg |
| Biotin (B7) | mcg |
| Folate (B9) | mcg |
| Vitamin B12 | mcg |

**Other:**

| Nutrient | Unit |
|----------|------|
| Choline | mg |
| Cholesterol | mg |

### Key Source Files

| File | Description |
|------|-------------|
| `lib/models/meal.dart` | Meal class with computed totals and serialization |
| `lib/models/ingredient.dart` | Ingredient class with scaling logic and all nutrient fields |
| `lib/model_config.dart` | Gemini response schemas (essential and comprehensive) |
| `lib/gemini_service.dart` | AI service: image analysis, search, daily evaluation |
| `lib/services/firestore_service.dart` | Firestore CRUD operations |
| `lib/services/storage_service.dart` | Firebase Storage image upload/retrieval |
| `lib/services/auth_service.dart` | Firebase Auth (anonymous + email linking) |
| `lib/services/meal_repository.dart` | Orchestrates saving meals (image + Firestore) |
| `lib/services/health_service.dart` | Apple Health / Health Connect integration |
