# CalorieTracker Flutter Conversion Guide

## App Overview
**EdanosAI: Food & Nutrition AI** is a comprehensive nutrition tracking app that uses Google's Gemini AI to analyze food photos/audio and provide detailed nutritional information. The app targets health-conscious users who want accurate, AI-powered food logging.

## Core Architecture

### Navigation Structure
- **TabView with 3 main tabs:**
  1. **Food Log** - Daily nutrition tracking with charts
  2. **Add Food** - AI-powered food analysis (camera/photos/audio)
  3. **Settings** - App configuration and subscriptions


### Data Persistence
 Use Firestore (cloud_firestore package) for offline and online database of the users food items.

## Core Features & Implementation

### 1. AI-Powered Food Analysis

- Use `firebase_ai` package 
- Implement similar schema validation with Dart models
- Camera: `camera` package, Audio: `flutter_sound`
- Image processing, create a thumbnail of each picture. 

### 2. Comprehensive Nutrition Tracking
**Data Model:**
- **Item** (main food entry): calories, macros, micros, timestamps

**Key Nutritional Data:**
- Macros: calories, protein, fat, carbs, fiber, sugar
- Micros: 13 vitamins (A, B1-B12, C, D, E, K), 8+ minerals
- Per-ingredient breakdown with adjustable quantities

let nutritionalValueSchema = Schema.object(
    properties: [
        "calories": .object(
            properties: [
                "value": .integer(description: "Caloric content value"),
                "unit": .string(description: "Unit for calories (typically kcal)"),
                "_range": .array(
                    items: .integer(description: "Lower and upper bounds of caloric content"),
                    description: "Array containing [lower_bound, upper_bound] of caloric estimate"
                )
            ]
        ),
        "water": .object(
            properties: [
                "value": .double(description: "For every drink, such as coffee, tea, water, juice, soda, beer, or other alcoholic drinks, predict the amount of water in the drink."),
                "unit": .string(description: "Unit for water (typically ml)")
            ]
        ),
        "alcohol": .object(
            properties: [
                "value": .double(description: "For drinks such as beer, or other alcoholic drinks, predict the amount of alcohol in the drink."),
                "unit": .string(description: "Unit for alcohol (typically ml)")
            ]
        ),
        "caffeine": .object(
                    properties: [
                        "value": .double(description: "For drinks such as coffee, tea, or other caffeinated drinks, predict the amount of caffeine in the drink."),
                        "unit": .string(description: "Unit for caffeine (typically mg)")
            ]
        ),
        "macronutrients": .object(
            properties: [
                "protein": .object(
                    properties: [
                        "value": .double(description: "Protein content value"),
                        "unit": .string(description: "Unit for protein (typically g)"),
                        "_range": .array(
                            items: .double(description: "Lower and upper bounds of protein content"),
                            description: "Array containing [lower_bound, upper_bound] of protein estimate"
                        )
                    ]
                ),
                "total_fat": .object(
                    properties: [
                        "value": .double(description: "Total fat content value"),
                        "unit": .string(description: "Unit for fat (typically g)"),
                        "_range": .array(
                            items: .double(description: "Lower and upper bounds of fat content"),
                            description: "Array containing [lower_bound, upper_bound] of fat estimate"
                        ),
                        "saturated_fat": .double(description: "Saturated fat content value"),
                        "unsaturated_fat": .double(description: "Unsaturated fat content value")
                    ],
                    optionalProperties: ["saturated_fat", "unsaturated_fat"]
                ),
                "carbohydrates": .object(
                    properties: [
                        "value": .double(description: "Total carbohydrates content value"),
                        "unit": .string(description: "Unit for carbohydrates (typically g)"),
                        "_range": .array(
                            items: .double(description: "Lower and upper bounds of carbohydrate content"),
                            description: "Array containing [lower_bound, upper_bound] of carbohydrate estimate"
                        ),
                        "fiber": .double(description: "Dietary fiber content value"),
                        "sugars": .double(description: "Sugars content value"),
                        "net_carbs": .double(description: "Net carbohydrates (total carbs minus fiber)")
                    ],
                    optionalProperties: ["fiber", "sugars", "net_carbs"]
                )
            ]
        ),
        "micronutrients": .object(
            properties: [
                "vitamins": .object(
                    properties: [
                        "vitamin_a": .object(
                            properties: [
                                "value": .double(description: "Vitamin A content value"),
                                "unit": .string(description: "Unit for vitamin A (typically mcg RAE)")
                            ]
                        ),
                        "vitamin_b1": .object(
                            properties: [
                                "value": .double(description: "Vitamin B1 (Thiamin) content value"),
                                "unit": .string(description: "Unit for vitamin B1 (typically mg)")
                            ]
                        ),
                        "vitamin_b2": .object(
                            properties: [
                                "value": .double(description: "Vitamin B2 (Riboflavin) content value"),
                                "unit": .string(description: "Unit for vitamin B2 (typically mg)")
                            ]
                        ),
                        "vitamin_b3": .object(
                            properties: [
                                "value": .double(description: "Vitamin B3 (Niacin) content value"),
                                "unit": .string(description: "Unit for vitamin B3 (typically mg)")
                            ]
                        ),
                        "vitamin_b5": .object(
                            properties: [
                                "value": .double(description: "Vitamin B5 (Pantothenic acid) content value"),
                                "unit": .string(description: "Unit for vitamin B5 (typically mg)")
                            ]
                        ),
                        "vitamin_b6": .object(
                            properties: [
                                "value": .double(description: "Vitamin B6 content value"),
                                "unit": .string(description: "Unit for vitamin B6 (typically mg)")
                            ]
                        ),
                        "vitamin_b7": .object(
                            properties: [
                                "value": .double(description: "Vitamin B7 (Biotin) content value"),
                                "unit": .string(description: "Unit for vitamin B7 (typically mcg)")
                            ]
                        ),
                        "vitamin_b9": .object(
                            properties: [
                                "value": .double(description: "Vitamin B9 (Folate) content value"),
                                "unit": .string(description: "Unit for vitamin B9 (typically mcg)")
                            ]
                        ),
                        "vitamin_b12": .object(
                            properties: [
                                "value": .double(description: "Vitamin B12 content value"),
                                "unit": .string(description: "Unit for vitamin B12 (typically mcg)")
                            ]
                        ),
                        "vitamin_c": .object(
                            properties: [
                                "value": .double(description: "Vitamin C content value"),
                                "unit": .string(description: "Unit for vitamin C (typically mg)")
                            ]
                        ),
                        "vitamin_d": .object(
                            properties: [
                                "value": .double(description: "Vitamin D content value"),
                                "unit": .string(description: "Unit for vitamin D (typically mcg)")
                            ]
                        ),
                        "vitamin_e": .object(
                            properties: [
                                "value": .double(description: "Vitamin E content value"),
                                "unit": .string(description: "Unit for vitamin E (typically mg)")
                            ]
                        ),
                        "vitamin_k": .object(
                            properties: [
                                "value": .double(description: "Vitamin K content value"),
                                "unit": .string(description: "Unit for vitamin K (typically mcg)")
                            ]
                        )
                    ],
                    optionalProperties: ["vitamin_a", "vitamin_b1", "vitamin_b2", "vitamin_b3", "vitamin_b5", 
                                        "vitamin_b6", "vitamin_b7", "vitamin_d", "vitamin_e", "vitamin_k"]
                ),
                "minerals": .object(
                    properties: [
                        "calcium": .object(
                            properties: [
                                "value": .double(description: "Calcium content value"),
                                "unit": .string(description: "Unit for calcium (typically mg)")
                            ]
                        ),
                        "copper": .object(
                            properties: [
                                "value": .double(description: "Copper content value"),
                                "unit": .string(description: "Unit for copper (typically mg)")
                            ]
                        ),
                        "iron": .object(
                            properties: [
                                "value": .double(description: "Iron content value"),
                                "unit": .string(description: "Unit for iron (typically mg)")
                            ]
                        ),
                        "magnesium": .object(
                            properties: [
                                "value": .double(description: "Magnesium content value"),
                                "unit": .string(description: "Unit for magnesium (typically mg)")
                            ]
                        ),
                        "manganese": .object(
                            properties: [
                                "value": .double(description: "Manganese content value"),
                                "unit": .string(description: "Unit for manganese (typically mg)")
                            ]
                        ),
                        "phosphorus": .object(
                            properties: [
                                "value": .double(description: "Phosphorus content value"),
                                "unit": .string(description: "Unit for phosphorus (typically mg)")
                            ]
                        ),
                        "potassium": .object(
                            properties: [
                                "value": .double(description: "Potassium content value"),
                                "unit": .string(description: "Unit for potassium (typically mg)")
                            ]
                        ),
                        "selenium": .object(
                            properties: [
                                "value": .double(description: "Selenium content value"),
                                "unit": .string(description: "Unit for selenium (typically mcg)")
                            ]
                        ),
                        "sodium": .object(
                            properties: [
                                "value": .double(description: "Sodium content value"),
                                "unit": .string(description: "Unit for sodium (typically mg)")
                            ]
                        ),
                        "zinc": .object(
                            properties: [
                                "value": .double(description: "Zinc content value"),
                                "unit": .string(description: "Unit for zinc (typically mg)")
                            ]
                        )
                    ],
                    optionalProperties: ["copper", "magnesium","potassium", "sodium"]
                ),
                
            ],
            optionalProperties: ["vitamins", "minerals"]
        )
    ],
    optionalProperties: ["micronutrients", "water", "alcohol", "caffeine"]
)

//  jsonSchema_foodAmounts to include nutritional values
let jsonSchema_nutritionalValues = Schema.object(
    properties: [
        "is_food": .boolean(description: "Indicates whether the input image contains food, be critical. It has to be a real food or food products!"),
        "is_drink": .boolean(description: "If the image shows a drink, such as coffee, water, juice, soda, beer, or other alcoholic drinks."),
        "food_name": .string(description: "Name of the food or dish identified in the image"),
        "description": .string(description: "A detailed description of the food, including visible components"),
        "ingredients": .array(
        items: .object(
            properties: [
            "name": .string(description: "Name of the ingredient"),
            "quantity": .double(description: "Quantity of the ingredient, be precise and use visual cues to estimate the quantity. In general be on the lower side for ingredients like rice, pasta, potatoes, bread."),
            "_quantity_range": .array(
                items: .double(description: "Lower and upper bounds of quantity estimate"),
                description: "Array containing [lower_bound, upper_bound] of quantity estimate"
            ),
            "unit": .enumeration(values: ["g", "ml"], description: "Try to estimate the the grams or ml."),
            "preparation_method": .enumeration(values: ["raw", "cooked"], description: "Whether the ingredient is raw or cooked"),
            "nutritional_values": nutritionalValueSchema
            ],
            optionalProperties: ["preparation_method", "nutritional_values", "_quantity_range"],
            )
        ),
        "confidence_summary": .string(description: "Overall confidence in the nutritional analysis")
    ]
)

**Calculation Logic:**
- Individual ingredient nutrition scales proportionally when amounts change, so when we have one ingredient like 100g chicken, which now has all the nutrtional values, such as 20g protein etc., and the user changes it to 90g chicken, then you need to change all the nutrtional values, so that they correspond to 90g chicken. 
- **No redistribution** between ingredients
- Aggregated daily/weekly summaries

### 3. Health Integration
**HealthKit Integration:**
- Reads: Active/resting energy burned
- Writes: All nutrition data to Apple Health
- Sync status tracking per meal
- **Flutter equivalent:** Use `health` package for similar functionality

### 5. Visual Analytics
**Chart Components:**
- Weekly nutrition trends (stacked bar charts)
- Daily macro breakdown visualization
- Progress indicators with goal tracking
- **Flutter equivalent:** Use `fl_chart` package

### 6. Settings & Customization
**Key Features:**
- Nutrition focus switching (calories/protein/carbs/fat/sugar)
- Daily nutrition goals (customizable per macro)
- Dark/light/system theme modes
- Notification scheduling (3 daily meal reminders), only when one hour prior the time no meal was tracked.
- HealthKit sync toggle

## Technical Implementation Details

### Dependencies (Flutter equivalents)
```yaml
dependencies:
  - firebase_ai #Gemini AI 
  - firebase_auth #User management with firebase authentification 
  - cloud_firestore #This is the database from firebase
  - firebase_app_check # Security
  - camera # Photo capture
  - image_picker # Photo selection
  - flutter_sound # Audio recording
  - health # HealthKit equivalent
  - in_app_purchase # StoreKit equivalent
  - fl_chart # Charts
  - shared_preferences # Settings storage
  - provider / riverpod # State management
  - image # Image processing
```

### Key UI Patterns
- **Card-based layouts** with rounded rectangles
- **Progress indicators** for nutrition goals
- **Modal sheets** for detailed views
- **Tab navigation** with badge indicators
- **Color-coded nutrition** (orange=fat, blue=protein, green=carbs)

### Data Flow Architecture
1. **Media Input** → AI Processing → Structured Response
2. **Nutrition Parsing** → Individual Ingredient Creation → Adjustable UI
3. **User Adjustments** → Real-time Recalculation → Database Storage
4. **Analytics Queries** → Chart Generation → UI Updates

### Critical Business Logic
- **Ingredient Quantity Scaling:** When user adjusts ingredient amounts, nutrition scales proportionally per ingredient
- **Daily Limits:** API call tracking with subscription-based tiers
- **Quick Add System:** Save frequently used meals for rapid logging
- **Date/Time Flexibility:** Users can adjust meal timestamps
- **Offline Capability:** Core app functions work without internet

### Advanced Features
- **Audio-to-text food logging** with AI interpretation
- **Ingredient search** with brand-specific database
- **Micronutrient tracking** (vitamins/minerals)
- **Weekly analytics** with trend visualization
- **Export/sync capabilities** via HealthKit integration

## Flutter-Specific Considerations

### State Management Approach
```dart
// Recommended structure
- FoodProvider (nutrition data, CRUD operations)
- SettingsProvider (user preferences, goals)
- SubscriptionProvider (premium features, purchases)
- AnalyticsProvider (charts, trends)
- AIProvider (Gemini integration, usage tracking)
```


