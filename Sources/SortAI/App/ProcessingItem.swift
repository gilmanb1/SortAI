// MARK: - Processing Item
// Tracks individual file state in the reactive pipeline
// Supports progressive processing with quick categorization first

import Foundation
import SwiftUI

/// Status of an individual file in the pipeline
enum FileStatus: Equatable {
    case queued
    case quickCategorizing  // Fast filename-based categorization
    case inspecting         // Eye: extracting data (slow for videos)
    case categorizing       // Brain: LLM analysis
    case reviewing          // Human review needed
    case accepted           // Human or Auto accepted
    case organizing         // Moving to destination
    case completed          // Done
    case failed(String)
    
    var label: String {
        switch self {
        case .queued: return "Queued"
        case .quickCategorizing: return "Analyzing..."
        case .inspecting: return "Extracting Content"
        case .categorizing: return "AI Categorizing"
        case .reviewing: return "Needs Review"
        case .accepted: return "Accepted"
        case .organizing: return "Moving"
        case .completed: return "Done"
        case .failed: return "Failed"
        }
    }
    
    var icon: String {
        switch self {
        case .queued: return "clock"
        case .quickCategorizing: return "sparkles"
        case .inspecting: return "eye.fill"
        case .categorizing: return "brain.fill"
        case .reviewing: return "person.badge.key.fill"
        case .accepted: return "checkmark.circle.fill"
        case .organizing: return "arrow.right.circle.fill"
        case .completed: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .queued: return .secondary
        case .quickCategorizing: return .cyan
        case .inspecting: return .purple
        case .categorizing: return .orange
        case .reviewing: return .yellow
        case .accepted: return .green
        case .organizing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    /// Priority for sorting (lower = higher in list)
    var sortPriority: Int {
        switch self {
        case .quickCategorizing: return 0  // Currently active - top
        case .inspecting: return 1         // Active - extracting
        case .categorizing: return 2       // Active - AI thinking
        case .organizing: return 3         // Active - moving files
        case .queued: return 4             // Waiting
        case .reviewing: return 5          // Needs human input
        case .accepted: return 6           // Done but not organized
        case .completed: return 7          // Fully done
        case .failed: return 8             // Failed - bottom
        }
    }
    
    /// Whether this status represents active processing
    var isActive: Bool {
        switch self {
        case .quickCategorizing, .inspecting, .categorizing, .organizing:
            return true
        default:
            return false
        }
    }
}

/// A single file item being processed by the app
@Observable
final class ProcessingItem: Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String
    var status: FileStatus = .queued
    var progress: Double = 0
    var result: ProcessingResult?
    var feedbackItem: FeedbackDisplayItem?
    
    // Quick categorization (shown immediately, then refined)
    var quickCategory: String?
    var quickSubcategory: String?
    var quickConfidence: Double = 0
    var isRefining: Bool = false  // True while full analysis is running
    
    // Provider tracking (v2.0)
    var provider: LLMProviderIdentifier?
    var escalatedFrom: LLMProviderIdentifier?  // Set if result came from escalation
    
    // Estimated processing time (for progress bar)
    var estimatedTime: TimeInterval?
    var startedAt: Date?
    
    init(url: URL) {
        self.url = url
        self.fileName = url.lastPathComponent
    }
    
    var canOrganize: Bool {
        status == .accepted || (status == .completed && result != nil)
    }
    
    var needsHumanReview: Bool {
        status == .reviewing
    }
    
    /// The category to display (quick first, then refined)
    var displayCategory: String {
        result?.brainResult.category ?? quickCategory ?? "..."
    }
    
    /// The subcategory to display
    var displaySubcategory: String? {
        result?.brainResult.subcategory ?? quickSubcategory
    }
    
    /// The confidence to display
    var displayConfidence: Double {
        result?.brainResult.confidence ?? quickConfidence
    }
    
    /// The full category path (for display in UI)
    /// Uses feedbackItem if available, otherwise uses the full path from BrainResult
    var fullCategoryPath: CategoryPath {
        // First, check if we have a feedbackItem with the full path
        if let feedback = feedbackItem {
            return feedback.categoryPath
        }
        
        // Next, use the full category path from BrainResult (includes all subcategories)
        if let brainResult = result?.brainResult {
            return brainResult.fullCategoryPath
        }
        
        // Fall back to quick categorization
        var components: [String] = []
        
        if let category = quickCategory, !category.isEmpty {
            components.append(category)
        }
        
        if let subcategory = quickSubcategory {
            components.append(subcategory)
        }
        
        return CategoryPath(components: components)
    }
    
    /// Elapsed time since processing started
    var elapsedTime: TimeInterval? {
        guard let started = startedAt else { return nil }
        return Date().timeIntervalSince(started)
    }
    
    /// Estimated progress based on elapsed time
    var estimatedProgress: Double {
        guard let elapsed = elapsedTime, let estimated = estimatedTime, estimated > 0 else {
            return progress
        }
        return min(0.95, elapsed / estimated)  // Cap at 95% to avoid showing 100% before done
    }
}

// MARK: - Progress Callback Types

/// Progress updates sent from pipeline to UI
enum ProcessingProgress: Sendable {
    case quickCategorized(category: String, subcategory: String?, confidence: Double)
    case inspecting
    case inspectionCached  // Using cached inspection result
    case categorizing
    case completed(ProcessingResult)
    case failed(String)
}

/// Callback for progress updates (MainActor-isolated for UI updates)
typealias ProgressCallback = @MainActor @Sendable (URL, ProcessingProgress) -> Void
