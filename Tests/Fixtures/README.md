# Test Fixtures

This directory contains test files and scripts for functional testing of SortAI.

## Test Files

The `TestFiles/` directory contains 100 realistic test files organized across 10 categories:

| Category | Files | Examples |
|----------|-------|----------|
| Work Documents | 15 | Q4_2023_Sales_Report.txt, Employee_Handbook_2024.txt |
| Personal Photos | 12 | IMG_20230615_Vacation_Beach.jpg, Christmas_2023_Family.jpg |
| Videos | 8 | VID_20230801_Summer_Trip.mp4, Tutorial_How_To_Code.mp4 |
| Music & Audio | 10 | Song_Summer_Vibes.txt, Podcast_Episode_Tech_Talk.txt |
| Recipes & Food | 8 | Recipe_Chocolate_Cake.txt, Meal_Plan_Weekly.txt |
| Educational | 10 | Study_Notes_Physics.txt, Research_Paper_Climate_Change.txt |
| Financial | 9 | Bank_Statement_January_2024.txt, Tax_Return_2023.txt |
| Health & Fitness | 8 | Workout_Routine_Monday.txt, Medical_Records_2024.txt |
| Travel | 10 | Flight_Booking_Confirmation.txt, Travel_Itinerary_Europe_2024.txt |
| Misc/Random | 10 | Random_Notes_Ideas.txt, Journal_Entry_March_2024.txt |

## Creating Test Files

To (re)create the test files:

```bash
./Tests/Fixtures/create_test_files.sh
```

This script:
- Cleans any existing test files
- Creates 100 new files with realistic names and content
- Organizes them in a flat structure (all in TestFiles/ root)

## Using in Tests

The functional tests automatically:
1. Scan the test files
2. Build a taxonomy
3. Organize files into categories
4. Reset files back to flat structure for next test

Example:

```swift
// Scan test files
let scanner = FilenameScanner(configuration: .init(
    maxFiles: 10000,
    includeHidden: false,
    excludedExtensions: [".ds_store", ".gitignore"],
    excludedDirectories: [],
    minFileSize: 1  // Allow small test files
))
let scanResult = try await scanner.scan(folder: fixturesPath)
let files = scanResult.files

// Build taxonomy
let builder = FastTaxonomyBuilder(configuration: .default)
let tree = await builder.buildInstant(from: files, rootName: "TestFiles")

// Verify categories were detected
#expect(tree.categoryCount > 1)
#expect(tree.totalFileCount == 100)
```

## Test File Reset

The `FunctionalOrganizationTests` suite includes a `resetTestFiles()` helper that:
- Finds all files recursively in TestFiles/
- Moves them back to the root (flat structure)
- Removes empty subdirectories
- Preserves the `.gitkeep` file

This ensures each test starts with a clean slate.

## Expected Categories

When running the taxonomy builder on these files, you should expect to see categories related to:

- **Photos/Images**: IMG_, PHOTO_, DSC_ prefixes
- **Videos**: VID_, Movie_, Tutorial_ prefixes
- **Documents/Work**: Report, Meeting, Contract, Invoice
- **Recipes/Food**: Recipe_, Meal_, Cookbook
- **Travel**: Flight, Hotel, Itinerary, Passport
- **Financial**: Bank, Tax, Investment, Insurance
- **Education**: Study, Lecture, Research, Course
- **Health**: Workout, Medical, Fitness, Nutrition

The exact categories will vary based on the taxonomy builder configuration and clustering algorithm.

## Notes

- Files have minimal content (just enough to pass the 100-byte minimum file size filter)
- File extensions (.txt, .jpg, .mp4) are used to simulate different file types
- Filenames are designed to trigger semantic clustering by keywords
- All files are safe to delete/recreate - they're generated from the script

