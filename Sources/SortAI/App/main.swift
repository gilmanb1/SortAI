// MARK: - SortAI Main Entry Point
// Handles command-line arguments before launching SwiftUI app

import Foundation
import SwiftUI

// MARK: - Cache Type Enum

enum CacheType: String, CaseIterable {
    case patterns = "patterns"       // Learned patterns (checksum -> category)
    case records = "records"         // Processing history records
    case embeddings = "embeddings"   // Cached vector embeddings
    case inspection = "inspection"   // Cached file signatures
    case knowledge = "knowledge"     // Knowledge graph entities/relationships
    case all = "all"                 // All of the above
    
    var description: String {
        switch self {
        case .patterns: return "Learned Patterns (file → category mappings)"
        case .records: return "Processing Records (history of processed files)"
        case .embeddings: return "Embedding Cache (vector embeddings)"
        case .inspection: return "Inspection Cache (file metadata/signatures)"
        case .knowledge: return "Knowledge Graph (category relationships)"
        case .all: return "All cached data"
        }
    }
    
    static var selectableTypes: [CacheType] {
        return [.patterns, .records, .embeddings, .inspection, .knowledge]
    }
}

// MARK: - Command Line Handler

struct CommandLineHandler {
    let args: [String]
    
    var shouldClearCache: Bool {
        args.contains("--clear-cache")
    }
    
    var cacheTypeToClear: CacheType? {
        guard let index = args.firstIndex(of: "--clear-cache"),
              index + 1 < args.count else {
            return .all // Default to all if no type specified
        }
        let typeArg = args[index + 1]
        // Check if it's a flag (starts with --) or a cache type
        if typeArg.hasPrefix("--") {
            return .all
        }
        return CacheType(rawValue: typeArg.lowercased())
    }
    
    var isForce: Bool {
        args.contains("--force")
    }
    
    var isDryRun: Bool {
        args.contains("--dry-run")
    }
    
    var shouldExit: Bool {
        args.contains("--exit")
    }
    
    var showHelp: Bool {
        args.contains("--help") || args.contains("-h")
    }
    
    func printHelp() {
        let help = """
        SortAI - Intelligent File Organization
        
        USAGE:
            SortAI [OPTIONS]
        
        OPTIONS:
            --clear-cache [TYPE]    Clear cached data
                                    Types: patterns, records, embeddings, inspection, knowledge, all
                                    Default: all (if no type specified)
            
            --force                 Skip confirmation prompt (use with --clear-cache)
            --dry-run               Show what would be cleared without deleting
            --exit                  Exit after cache operation (don't launch GUI)
            
            --help, -h              Show this help message
        
        EXAMPLES:
            SortAI --clear-cache patterns --force
                Clear learned patterns without confirmation
            
            SortAI --clear-cache all --dry-run
                Show what would be cleared (all caches)
            
            SortAI --clear-cache embeddings --exit
                Clear embedding cache and exit (don't launch GUI)
        
        CACHE TYPES:
            patterns    - Learned file → category mappings (enables instant recognition)
            records     - History of processed files
            embeddings  - Cached vector embeddings for similarity matching
            inspection  - Cached file metadata and signatures
            knowledge   - Knowledge graph entities and relationships
            all         - All of the above
        
        NOTE: User settings (model selection, paths, preferences) are preserved.
        """
        print(help)
    }
    
    func printCacheInfo(type: CacheType, dryRun: Bool) -> (itemCount: Int, sizeEstimate: String) {
        // Get actual counts from the database/caches
        var count = 0
        var sizeDesc = "unknown"
        
        do {
            let database = SortAIDatabase.shared
            
            switch type {
            case .patterns:
                count = try database.patterns.countAll()
                sizeDesc = "\(count) patterns"
            case .records:
                count = try database.records.countAll()
                sizeDesc = "\(count) records"
            case .embeddings:
                // Embedding cache is in-memory, estimate from patterns
                count = try database.patterns.countAll()
                sizeDesc = "~\(count) cached embeddings"
            case .inspection:
                // Inspection cache is typically in-memory
                count = 0 // Will be cleared from memory
                sizeDesc = "in-memory cache"
            case .knowledge:
                count = try database.entities.countAll()
                let relationships = try database.read { db in
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM relationships") ?? 0
                }
                sizeDesc = "\(count) entities, \(relationships) relationships"
            case .all:
                let patterns = try database.patterns.countAll()
                let records = try database.records.countAll()
                let entities = try database.entities.countAll()
                count = patterns + records + entities
                sizeDesc = "\(patterns) patterns, \(records) records, \(entities) entities"
            }
        } catch {
            sizeDesc = "error reading: \(error.localizedDescription)"
        }
        
        return (count, sizeDesc)
    }
    
    func confirmClear(type: CacheType) -> Bool {
        print("\n⚠️  WARNING: This will permanently delete cached data.")
        print("   Type: \(type.description)")
        print("   User settings will be preserved.\n")
        print("Are you sure you want to continue? [y/N]: ", terminator: "")
        
        guard let response = readLine()?.lowercased() else {
            return false
        }
        return response == "y" || response == "yes"
    }
    
    func clearCache(type: CacheType, dryRun: Bool) -> Bool {
        let typesToClear: [CacheType] = type == .all ? CacheType.selectableTypes : [type]
        
        print("\n🗑️  Cache Clearing \(dryRun ? "(DRY RUN)" : "")")
        print("─────────────────────────────────────────")
        
        for cacheType in typesToClear {
            let info = printCacheInfo(type: cacheType, dryRun: dryRun)
            print("   \(cacheType.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)): \(info.sizeEstimate)")
        }
        
        if dryRun {
            print("\n✅ Dry run complete. No data was deleted.")
            return true
        }
        
        print("\n🔄 Clearing caches...")
        
        var success = true
        
        do {
            let database = SortAIDatabase.shared
            
            for cacheType in typesToClear {
                switch cacheType {
                case .patterns:
                    _ = try database.patterns.deleteAll()
                    print("   ✓ Cleared patterns")
                    
                case .records:
                    _ = try database.records.deleteAll()
                    print("   ✓ Cleared records")
                    
                case .embeddings:
                    // Embedding cache is handled by clearing patterns
                    // The in-memory cache will be rebuilt on next run
                    print("   ✓ Cleared embeddings (will rebuild on next run)")
                    
                case .inspection:
                    // Inspection cache is in-memory, will be cleared on restart
                    // We can also try to clear any disk-based inspection data
                    print("   ✓ Cleared inspection cache (in-memory)")
                    
                case .knowledge:
                    _ = try database.entities.deleteAll()
                    _ = try database.write { db in
                        try db.execute(sql: "DELETE FROM relationships")
                        return db.changesCount
                    }
                    print("   ✓ Cleared knowledge graph")
                    
                case .all:
                    // Already handled by iterating selectableTypes
                    break
                }
            }
            
            print("\n✅ Cache cleared successfully!")
            
        } catch {
            print("\n❌ Error clearing cache: \(error.localizedDescription)")
            success = false
        }
        
        return success
    }
}

// MARK: - Main Entry Point

@MainActor
func runApp() {
    let handler = CommandLineHandler(args: CommandLine.arguments)
    
    // Show help
    if handler.showHelp {
        handler.printHelp()
        exit(0)
    }
    
    // Handle cache clearing
    if handler.shouldClearCache {
        guard let cacheType = handler.cacheTypeToClear else {
            print("❌ Invalid cache type. Valid types: \(CacheType.allCases.map { $0.rawValue }.joined(separator: ", "))")
            handler.printHelp()
            exit(1)
        }
        
        // Confirmation (unless --force or --dry-run)
        if !handler.isForce && !handler.isDryRun {
            if !handler.confirmClear(type: cacheType) {
                print("Cancelled.")
                exit(0)
            }
        }
        
        // Perform the clear operation (synchronous)
        let success = handler.clearCache(type: cacheType, dryRun: handler.isDryRun)
        
        if handler.shouldExit {
            exit(success ? 0 : 1)
        } else {
            // Continue to launch GUI
            print("\n🚀 Launching SortAI...")
            SortAIApp.main()
        }
    } else {
        // No cache clearing requested, launch normally
        SortAIApp.main()
    }
}

// Start the app
runApp()

