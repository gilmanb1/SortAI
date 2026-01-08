// MARK: - Category Accuracy Tests
// Tests system accuracy against known file categorizations

import Testing
import Foundation
@testable import SortAI

@Suite("Category Accuracy Tests")
struct CategoryAccuracyTests {
    
    // MARK: - Known Categories
    
    /// Expected categories for test files based on their names
    struct KnownCategory {
        let filename: String
        let expectedCategory: String
        let alternateCategories: [String] // Acceptable alternatives
        
        init(_ filename: String, _ category: String, alternates: [String] = []) {
            self.filename = filename
            self.expectedCategory = category
            self.alternateCategories = alternates
        }
    }
    
    // Define known categorizations for our test files
    static let knownCategories: [KnownCategory] = [
        // Work Documents (15 files)
        KnownCategory("Q4_2023_Sales_Report.txt", "Work", alternates: ["Business", "Documents", "Reports"]),
        KnownCategory("2024_Budget_Proposal.txt", "Work", alternates: ["Business", "Documents", "Finance"]),
        KnownCategory("Employee_Handbook_2024.txt", "Work", alternates: ["Business", "Documents", "HR"]),
        KnownCategory("Meeting_Notes_Jan_15_2024.txt", "Work", alternates: ["Business", "Documents", "Notes"]),
        KnownCategory("Project_Roadmap_Q1.txt", "Work", alternates: ["Business", "Documents", "Projects"]),
        
        // Personal Photos (12 files)
        KnownCategory("IMG_20230615_Vacation_Beach.jpg", "Photos", alternates: ["Images", "Pictures", "Personal", "Vacation"]),
        KnownCategory("IMG_20230616_Sunset_View.jpg", "Photos", alternates: ["Images", "Pictures", "Personal"]),
        KnownCategory("PHOTO_Family_Reunion_2023.jpg", "Photos", alternates: ["Images", "Pictures", "Personal", "Family"]),
        KnownCategory("DSC_0001_Wedding_Ceremony.jpg", "Photos", alternates: ["Images", "Pictures", "Personal", "Wedding"]),
        KnownCategory("Christmas_2023_Family.jpg", "Photos", alternates: ["Images", "Pictures", "Personal", "Holiday"]),
        
        // Videos (8 files)
        KnownCategory("VID_20230801_Summer_Trip.mp4", "Videos", alternates: ["Media", "Movies", "Personal"]),
        KnownCategory("Tutorial_How_To_Code.mp4", "Videos", alternates: ["Media", "Education", "Tutorial"]),
        KnownCategory("Conference_Keynote_2024.mp4", "Videos", alternates: ["Media", "Work", "Business"]),
        
        // Recipes & Food (8 files)
        KnownCategory("Recipe_Chocolate_Cake.txt", "Recipes", alternates: ["Food", "Cooking", "Kitchen"]),
        KnownCategory("Recipe_Pasta_Carbonara.txt", "Recipes", alternates: ["Food", "Cooking", "Kitchen"]),
        KnownCategory("Meal_Plan_Weekly.txt", "Recipes", alternates: ["Food", "Cooking", "Health"]),
        KnownCategory("Cookbook_Italian_Dishes.txt", "Recipes", alternates: ["Food", "Cooking", "Kitchen"]),
        
        // Educational (10 files)
        KnownCategory("Study_Notes_Physics.txt", "Education", alternates: ["School", "Study", "Notes"]),
        KnownCategory("Research_Paper_Climate_Change.txt", "Education", alternates: ["School", "Research", "Documents"]),
        KnownCategory("Course_Materials_Python.txt", "Education", alternates: ["School", "Programming", "Tutorial"]),
        KnownCategory("Tutorial_Machine_Learning.txt", "Education", alternates: ["School", "Programming", "Tutorial"]),
        
        // Financial (9 files)
        KnownCategory("Bank_Statement_January_2024.txt", "Financial", alternates: ["Finance", "Money", "Documents"]),
        KnownCategory("Tax_Return_2023.txt", "Financial", alternates: ["Finance", "Money", "Tax", "Documents"]),
        KnownCategory("Investment_Portfolio_Summary.txt", "Financial", alternates: ["Finance", "Money", "Investments"]),
        KnownCategory("Insurance_Policy_Auto.txt", "Financial", alternates: ["Finance", "Documents", "Insurance"]),
        
        // Health & Fitness (8 files)
        KnownCategory("Workout_Routine_Monday.txt", "Health", alternates: ["Fitness", "Exercise", "Personal"]),
        KnownCategory("Medical_Records_2024.txt", "Health", alternates: ["Medical", "Documents", "Personal"]),
        KnownCategory("Nutrition_Log_Weekly.txt", "Health", alternates: ["Fitness", "Food", "Personal"]),
        KnownCategory("Running_Training_Plan.txt", "Health", alternates: ["Fitness", "Exercise", "Sports"]),
        
        // Travel (10 files)
        KnownCategory("Flight_Booking_Confirmation.txt", "Travel", alternates: ["Trip", "Vacation", "Documents"]),
        KnownCategory("Hotel_Reservation_Paris.txt", "Travel", alternates: ["Trip", "Vacation", "Documents"]),
        KnownCategory("Travel_Itinerary_Europe_2024.txt", "Travel", alternates: ["Trip", "Vacation", "Documents"]),
        KnownCategory("City_Guide_Tokyo.txt", "Travel", alternates: ["Trip", "Vacation", "Guide"]),
    ]
    
    // MARK: - Helper Methods
    
    static func testFixturesPath() -> URL {
        let currentFile = URL(fileURLWithPath: #filePath)
        let testsDir = currentFile.deletingLastPathComponent().deletingLastPathComponent()
        return testsDir.appendingPathComponent("Fixtures/TestFiles")
    }
    
    func matchesExpectedCategory(assignedPath: [String], expected: KnownCategory) -> Bool {
        let assignedCategories = assignedPath.map { $0.lowercased() }
        let expectedLower = expected.expectedCategory.lowercased()
        
        // Check if any assigned category matches expected or alternates
        for category in assignedCategories {
            if category == expectedLower {
                return true
            }
            
            // Check partial matches (e.g., "photos" in "Personal Photos")
            if category.contains(expectedLower) || expectedLower.contains(category) {
                return true
            }
            
            // Check alternates
            for alternate in expected.alternateCategories {
                let alternateLower = alternate.lowercased()
                if category == alternateLower || category.contains(alternateLower) || alternateLower.contains(category) {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Tests
    
    @Test("Categorization accuracy with known files")
    func testCategorizationAccuracy() async throws {
        let fixturesPath = Self.testFixturesPath()
        
        // Scan files
        let scanner = FilenameScanner(configuration: .init(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".gitignore"],
            excludedDirectories: [],
            minFileSize: 1
        ))
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        #expect(files.count > 50, "Should have scanned test files")
        
        // Build taxonomy
        let builder = FastTaxonomyBuilder(
            configuration: .init(
                targetCategoryCount: 10,
                separateFileTypes: false,
                autoRefine: false,
                refinementModel: "llama3.2",
                refinementBatchSize: 50
            )
        )
        
        let tree = await builder.buildInstant(from: files, rootName: "TestFiles")
        
        #expect(tree.categoryCount > 1, "Should create categories")
        
        // Analyze accuracy
        var correctCount = 0
        var totalChecked = 0
        var results: [(filename: String, expected: String, assigned: [String], correct: Bool)] = []
        
        for knownCat in Self.knownCategories {
            // Find the file in the tree
            if let file = files.first(where: { $0.filename == knownCat.filename }),
               let assignment = tree.allAssignments().first(where: { $0.fileId == file.id }) {
                
                // Get the category path for this file
                if let node = tree.node(byId: assignment.categoryId) {
                    let categoryPath = tree.pathToNode(node).map { $0.name }
                    
                    let isCorrect = matchesExpectedCategory(assignedPath: categoryPath, expected: knownCat)
                    
                    if isCorrect {
                        correctCount += 1
                    }
                    
                    totalChecked += 1
                    results.append((
                        filename: knownCat.filename,
                        expected: knownCat.expectedCategory,
                        assigned: categoryPath,
                        correct: isCorrect
                    ))
                }
            }
        }
        
        let accuracy = totalChecked > 0 ? Double(correctCount) / Double(totalChecked) : 0.0
        
        NSLog("📊 [Accuracy Test] Checked: \(totalChecked) files")
        NSLog("📊 [Accuracy Test] Correct: \(correctCount) (\(String(format: "%.1f", accuracy * 100))%)")
        NSLog("📊 [Accuracy Test] Incorrect: \(totalChecked - correctCount)")
        
        // Log some examples
        let incorrectResults = results.filter { !$0.correct }.prefix(5)
        if !incorrectResults.isEmpty {
            NSLog("📊 [Accuracy Test] Example incorrect categorizations:")
            for result in incorrectResults {
                NSLog("📊   - \(result.filename)")
                NSLog("📊     Expected: \(result.expected)")
                NSLog("📊     Assigned: \(result.assigned.joined(separator: " > "))")
            }
        }
        
        let correctResults = results.filter { $0.correct }.prefix(3)
        if !correctResults.isEmpty {
            NSLog("📊 [Accuracy Test] Example correct categorizations:")
            for result in correctResults {
                NSLog("📊   ✓ \(result.filename) → \(result.assigned.joined(separator: " > "))")
            }
        }
        
        // We expect at least 30% accuracy with filename-only classification
        // (This is a reasonable baseline - deep analysis would improve it significantly)
        #expect(accuracy >= 0.3, "Should achieve at least 30% categorization accuracy")
    }
    
    @Test("Category detection for specific file types")
    func testCategoryDetectionByType() async throws {
        let fixturesPath = Self.testFixturesPath()
        
        let scanner = FilenameScanner(configuration: .init(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".gitignore"],
            excludedDirectories: [],
            minFileSize: 1
        ))
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        let builder = FastTaxonomyBuilder(configuration: .default)
        let tree = await builder.buildInstant(from: files, rootName: "TestFiles")
        
        let categoryNames = tree.allCategories().map { $0.name.lowercased() }
        
        // Check for photo-related categories
        let hasPhotoCategory = categoryNames.contains { name in
            name.contains("photo") || name.contains("image") || name.contains("picture")
        }
        
        // Check for video-related categories
        let hasVideoCategory = categoryNames.contains { name in
            name.contains("video") || name.contains("movie") || name.contains("media")
        }
        
        // Check for document/work-related categories
        let hasDocumentCategory = categoryNames.contains { name in
            name.contains("document") || name.contains("work") || name.contains("business")
        }
        
        NSLog("📊 [Type Detection] Has photo category: \(hasPhotoCategory)")
        NSLog("📊 [Type Detection] Has video category: \(hasVideoCategory)")
        NSLog("📊 [Type Detection] Has document category: \(hasDocumentCategory)")
        NSLog("📊 [Type Detection] All categories: \(categoryNames.joined(separator: ", "))")
        
        // At least one of these should be detected
        #expect(hasPhotoCategory || hasVideoCategory || hasDocumentCategory,
                "Should detect at least one major file type category")
    }
    
    @Test("Category confidence for known files")
    func testCategoryConfidence() async throws {
        let fixturesPath = Self.testFixturesPath()
        
        let scanner = FilenameScanner(configuration: .init(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".gitignore"],
            excludedDirectories: [],
            minFileSize: 1
        ))
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        let builder = FastTaxonomyBuilder(configuration: .default)
        let tree = await builder.buildInstant(from: files, rootName: "TestFiles")
        
        let assignments = tree.allAssignments()
        
        // Calculate average confidence
        let avgConfidence = assignments.isEmpty ? 0 :
            assignments.reduce(0.0) { $0 + $1.confidence } / Double(assignments.count)
        
        // Find high and low confidence files
        let highConfidence = assignments.filter { $0.confidence >= 0.8 }
        let lowConfidence = assignments.filter { $0.confidence < 0.5 }
        
        NSLog("📊 [Confidence] Average: \(String(format: "%.2f", avgConfidence))")
        NSLog("📊 [Confidence] High (≥0.8): \(highConfidence.count)")
        NSLog("📊 [Confidence] Low (<0.5): \(lowConfidence.count)")
        
        // Log some examples
        if !highConfidence.isEmpty {
            NSLog("📊 [Confidence] High confidence examples:")
            for assignment in highConfidence.prefix(3) {
                NSLog("📊   ✓ \(assignment.filename): \(String(format: "%.0f", assignment.confidence * 100))%")
            }
        }
        
        if !lowConfidence.isEmpty {
            NSLog("📊 [Confidence] Low confidence examples (need deep analysis):")
            for assignment in lowConfidence.prefix(3) {
                NSLog("📊   ⚠️ \(assignment.filename): \(String(format: "%.0f", assignment.confidence * 100))%")
            }
        }
        
        // Should have reasonable confidence levels
        #expect(avgConfidence > 0, "Should have non-zero average confidence")
        #expect(avgConfidence >= 0.5, "Should have at least moderate average confidence")
        
        // Note: filename-based classification typically has moderate confidence (0.6-0.75)
        // Deep content analysis would push confidence higher
    }
    
    @Test("Taxonomy depth for test files")
    func testTaxonomyDepth() async throws {
        let fixturesPath = Self.testFixturesPath()
        
        let scanner = FilenameScanner(configuration: .init(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".gitignore"],
            excludedDirectories: [],
            minFileSize: 1
        ))
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        let builder = FastTaxonomyBuilder(configuration: .default)
        let tree = await builder.buildInstant(from: files, rootName: "TestFiles")
        
        let maxDepth = tree.maxDepth
        let categoryCount = tree.categoryCount
        
        NSLog("📊 [Depth] Maximum depth: \(maxDepth)")
        NSLog("📊 [Depth] Total categories: \(categoryCount)")
        NSLog("📊 [Depth] Files per category (avg): \(files.count / max(categoryCount - 1, 1))")
        
        // Should create reasonable hierarchy
        #expect(maxDepth >= 1, "Should have some depth")
        #expect(maxDepth <= 7, "Should not exceed reasonable depth")
        #expect(categoryCount >= 2, "Should create multiple categories")
    }
    
    @Test("File distribution across categories")
    func testFileDistribution() async throws {
        let fixturesPath = Self.testFixturesPath()
        
        let scanner = FilenameScanner(configuration: .init(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".gitignore"],
            excludedDirectories: [],
            minFileSize: 1
        ))
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        let builder = FastTaxonomyBuilder(configuration: .default)
        let tree = await builder.buildInstant(from: files, rootName: "TestFiles")
        
        let categories = tree.allCategories().filter { $0.name != tree.root.name }
        let distribution = categories.map { ($0.name, $0.totalFileCount) }
            .sorted { $0.1 > $1.1 }
        
        NSLog("📊 [Distribution] File distribution across categories:")
        for (name, count) in distribution.prefix(10) {
            let percentage = files.count > 0 ? Double(count) / Double(files.count) * 100 : 0
            NSLog("📊   - \(name): \(count) files (\(String(format: "%.1f", percentage))%)")
        }
        
        // Should distribute files across categories (not all in one)
        if categories.count > 1 {
            let maxCategorySize = distribution.first?.1 ?? 0
            let distributionRatio = files.count > 0 ? Double(maxCategorySize) / Double(files.count) : 1.0
            
            #expect(distributionRatio < 0.9, "Should not put 90% of files in one category")
        }
    }
}

