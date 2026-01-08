// MARK: - Spherical K-Means Clustering
// Spec requirement: "perform bounded recursive clustering (spherical k-means or HDBSCAN)"

import Foundation

// MARK: - Cluster Result

struct SphericalCluster: Identifiable, Sendable {
    let id: Int
    var centroid: [Float]
    var memberIndices: [Int]
    var memberSimilarities: [Float]  // Cosine similarity to centroid
    
    var size: Int { memberIndices.count }
    
    /// Average similarity of members to centroid (cluster cohesion)
    var cohesion: Float {
        guard !memberSimilarities.isEmpty else { return 0 }
        return memberSimilarities.reduce(0, +) / Float(memberSimilarities.count)
    }
    
    /// Variance in similarities (cluster tightness)
    var variance: Float {
        guard memberSimilarities.count > 1 else { return 0 }
        let mean = cohesion
        let sumSquaredDiff = memberSimilarities.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        return sumSquaredDiff / Float(memberSimilarities.count - 1)
    }
}

// MARK: - Clustering Configuration

struct SphericalKMeansConfiguration: Sendable {
    /// Number of clusters (k)
    let k: Int
    
    /// Maximum iterations
    let maxIterations: Int
    
    /// Convergence tolerance (cosine similarity of centroid change)
    let tolerance: Float
    
    /// Number of initializations (best result kept)
    let nInit: Int
    
    /// Minimum cluster size (clusters below this may be merged)
    let minClusterSize: Int
    
    /// Random seed for reproducibility (nil for random)
    let randomSeed: UInt64?
    
    static func `default`(k: Int) -> SphericalKMeansConfiguration {
        SphericalKMeansConfiguration(
            k: k,
            maxIterations: 100,
            tolerance: 0.0001,
            nInit: 3,
            minClusterSize: 2,
            randomSeed: nil
        )
    }
    
    static func fast(k: Int) -> SphericalKMeansConfiguration {
        SphericalKMeansConfiguration(
            k: k,
            maxIterations: 50,
            tolerance: 0.001,
            nInit: 1,
            minClusterSize: 1,
            randomSeed: nil
        )
    }
}

// MARK: - Spherical K-Means Clusterer

/// Implements spherical k-means clustering for normalized embeddings
/// Uses cosine similarity (dot product for unit vectors) as distance metric
struct SphericalKMeans: Sendable {
    
    private let config: SphericalKMeansConfiguration
    
    init(configuration: SphericalKMeansConfiguration) {
        self.config = configuration
    }
    
    // MARK: - Main Clustering
    
    /// Cluster embeddings into k groups
    /// - Parameter embeddings: Array of normalized embedding vectors
    /// - Returns: Array of cluster assignments and cluster info
    func cluster(_ embeddings: [[Float]]) -> SphericalKMeansResult {
        guard !embeddings.isEmpty else {
            return SphericalKMeansResult(clusters: [], assignments: [], iterations: 0, converged: true)
        }
        
        guard embeddings.count >= config.k else {
            // Fewer points than clusters - each point is its own cluster
            return createTrivialClusters(embeddings)
        }
        
        // Ensure all embeddings are normalized
        let normalizedEmbeddings = embeddings.map { l2Normalize($0) }
        
        // Run multiple initializations and keep best
        var bestResult: SphericalKMeansResult?
        var bestInertia: Float = .infinity
        
        for initIndex in 0..<config.nInit {
            let seed = config.randomSeed.map { $0 + UInt64(initIndex) }
            let result = runSingleKMeans(normalizedEmbeddings, seed: seed)
            
            let inertia = calculateInertia(embeddings: normalizedEmbeddings, result: result)
            if inertia < bestInertia {
                bestInertia = inertia
                bestResult = result
            }
        }
        
        return bestResult ?? createTrivialClusters(embeddings)
    }
    
    // MARK: - Single K-Means Run
    
    private func runSingleKMeans(_ embeddings: [[Float]], seed: UInt64?) -> SphericalKMeansResult {
        let dimensions = embeddings[0].count
        
        // Initialize centroids using k-means++
        var centroids = initializeCentroidsKMeansPlusPlus(embeddings, seed: seed)
        var assignments = [Int](repeating: 0, count: embeddings.count)
        var converged = false
        var iterations = 0
        
        for iter in 0..<config.maxIterations {
            iterations = iter + 1
            
            // Assignment step: assign each point to nearest centroid
            var newAssignments = [Int](repeating: 0, count: embeddings.count)
            for (i, embedding) in embeddings.enumerated() {
                newAssignments[i] = findNearestCentroid(embedding, centroids: centroids)
            }
            
            // Check for convergence
            if newAssignments == assignments && iter > 0 {
                converged = true
                break
            }
            assignments = newAssignments
            
            // Update step: recalculate centroids
            var newCentroids = [[Float]](repeating: [Float](repeating: 0, count: dimensions), count: config.k)
            var clusterCounts = [Int](repeating: 0, count: config.k)
            
            for (i, assignment) in assignments.enumerated() {
                for d in 0..<dimensions {
                    newCentroids[assignment][d] += embeddings[i][d]
                }
                clusterCounts[assignment] += 1
            }
            
            // Normalize centroids (project to unit sphere)
            for c in 0..<config.k {
                if clusterCounts[c] > 0 {
                    centroids[c] = l2Normalize(newCentroids[c])
                }
                // Keep old centroid if cluster is empty
            }
        }
        
        // Build cluster objects
        let clusters = buildClusters(embeddings: embeddings, centroids: centroids, assignments: assignments)
        
        return SphericalKMeansResult(
            clusters: clusters,
            assignments: assignments,
            iterations: iterations,
            converged: converged
        )
    }
    
    // MARK: - Initialization (k-means++)
    
    private func initializeCentroidsKMeansPlusPlus(_ embeddings: [[Float]], seed: UInt64?) -> [[Float]] {
        var rng = seed.map { SeededRNG(seed: $0) }
        let n = embeddings.count
        var centroids: [[Float]] = []
        var chosen = Set<Int>()
        
        // Choose first centroid randomly
        let first = rng?.next(upperBound: UInt64(n)) ?? UInt64.random(in: 0..<UInt64(n))
        centroids.append(embeddings[Int(first)])
        chosen.insert(Int(first))
        
        // Choose remaining centroids with probability proportional to distance squared
        while centroids.count < config.k {
            var distances = [Float](repeating: 0, count: n)
            var totalDistance: Float = 0
            
            for i in 0..<n {
                if chosen.contains(i) {
                    distances[i] = 0
                    continue
                }
                
                // Distance = 1 - max similarity to any centroid
                var maxSim: Float = 0
                for centroid in centroids {
                    let sim = dotProduct(embeddings[i], centroid)
                    maxSim = max(maxSim, sim)
                }
                distances[i] = (1 - maxSim) * (1 - maxSim)  // Squared distance
                totalDistance += distances[i]
            }
            
            // Sample proportional to distance squared
            var threshold = Float(rng?.nextFloat() ?? Float.random(in: 0..<1)) * totalDistance
            var selectedIndex = 0
            
            for i in 0..<n {
                threshold -= distances[i]
                if threshold <= 0 {
                    selectedIndex = i
                    break
                }
            }
            
            if !chosen.contains(selectedIndex) {
                centroids.append(embeddings[selectedIndex])
                chosen.insert(selectedIndex)
            }
        }
        
        return centroids
    }
    
    // MARK: - Helper Functions
    
    private func findNearestCentroid(_ embedding: [Float], centroids: [[Float]]) -> Int {
        var bestIndex = 0
        var bestSimilarity: Float = -.infinity
        
        for (i, centroid) in centroids.enumerated() {
            let similarity = dotProduct(embedding, centroid)
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestIndex = i
            }
        }
        
        return bestIndex
    }
    
    private func buildClusters(embeddings: [[Float]], centroids: [[Float]], assignments: [Int]) -> [SphericalCluster] {
        var clusters: [SphericalCluster] = []
        
        for c in 0..<config.k {
            var memberIndices: [Int] = []
            var memberSimilarities: [Float] = []
            
            for (i, assignment) in assignments.enumerated() {
                if assignment == c {
                    memberIndices.append(i)
                    memberSimilarities.append(dotProduct(embeddings[i], centroids[c]))
                }
            }
            
            clusters.append(SphericalCluster(
                id: c,
                centroid: centroids[c],
                memberIndices: memberIndices,
                memberSimilarities: memberSimilarities
            ))
        }
        
        return clusters
    }
    
    private func calculateInertia(embeddings: [[Float]], result: SphericalKMeansResult) -> Float {
        // Inertia = sum of (1 - similarity) for all points
        var inertia: Float = 0
        
        for cluster in result.clusters {
            for sim in cluster.memberSimilarities {
                inertia += (1 - sim)
            }
        }
        
        return inertia
    }
    
    private func createTrivialClusters(_ embeddings: [[Float]]) -> SphericalKMeansResult {
        var clusters: [SphericalCluster] = []
        var assignments: [Int] = []
        
        for (i, embedding) in embeddings.enumerated() {
            clusters.append(SphericalCluster(
                id: i,
                centroid: embedding,
                memberIndices: [i],
                memberSimilarities: [1.0]
            ))
            assignments.append(i)
        }
        
        return SphericalKMeansResult(clusters: clusters, assignments: assignments, iterations: 0, converged: true)
    }
    
    // MARK: - Vector Operations
    
    private func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var result: Float = 0
        for i in 0..<a.count {
            result += a[i] * b[i]
        }
        return result
    }
    
    private func l2Normalize(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}

// MARK: - Result

struct SphericalKMeansResult: Sendable {
    let clusters: [SphericalCluster]
    let assignments: [Int]  // Cluster assignment for each input
    let iterations: Int
    let converged: Bool
    
    /// Non-empty clusters
    var nonEmptyClusters: [SphericalCluster] {
        clusters.filter { !$0.memberIndices.isEmpty }
    }
    
    /// Average cluster cohesion
    var averageCohesion: Float {
        let nonEmpty = nonEmptyClusters
        guard !nonEmpty.isEmpty else { return 0 }
        return nonEmpty.map { $0.cohesion }.reduce(0, +) / Float(nonEmpty.count)
    }
}

// MARK: - Seeded RNG

/// Simple seeded random number generator for reproducibility
private struct SeededRNG {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        // Xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    
    mutating func next(upperBound: UInt64) -> UInt64 {
        return next() % upperBound
    }
    
    mutating func nextFloat() -> Float {
        return Float(next()) / Float(UInt64.max)
    }
}

// MARK: - Elbow Method for Optimal K

extension SphericalKMeans {
    
    /// Find optimal k using elbow method
    static func findOptimalK(
        embeddings: [[Float]],
        kRange: ClosedRange<Int> = 2...10,
        maxIterations: Int = 50
    ) -> (optimalK: Int, inertias: [Int: Float]) {
        var inertias: [Int: Float] = [:]
        
        for k in kRange {
            let config = SphericalKMeansConfiguration.fast(k: k)
            let kmeans = SphericalKMeans(configuration: config)
            let result = kmeans.cluster(embeddings)
            
            // Calculate inertia
            var inertia: Float = 0
            for cluster in result.clusters {
                inertia += cluster.memberSimilarities.map { 1 - $0 }.reduce(0, +)
            }
            inertias[k] = inertia
        }
        
        // Find elbow using second derivative
        let sortedKs = kRange.sorted()
        var maxCurvature: Float = 0
        var optimalK = sortedKs.first ?? 2
        
        for i in 1..<(sortedKs.count - 1) {
            let k = sortedKs[i]
            guard let prev = inertias[sortedKs[i-1]],
                  let curr = inertias[k],
                  let next = inertias[sortedKs[i+1]] else { continue }
            
            // Second derivative (curvature)
            let curvature = abs(prev - 2 * curr + next)
            if curvature > maxCurvature {
                maxCurvature = curvature
                optimalK = k
            }
        }
        
        return (optimalK, inertias)
    }
}

// MARK: - Hierarchical Extension

extension SphericalKMeans {
    
    /// Perform hierarchical clustering by recursively splitting clusters
    static func hierarchicalCluster(
        embeddings: [[Float]],
        maxDepth: Int,
        minClusterSize: Int = 3,
        targetClustersPerLevel: Int = 3
    ) -> HierarchicalClusterNode {
        let root = HierarchicalClusterNode(
            id: "root",
            depth: 0,
            memberIndices: Array(0..<embeddings.count),
            centroid: calculateCentroid(embeddings, indices: Array(0..<embeddings.count))
        )
        
        recursiveCluster(
            node: root,
            embeddings: embeddings,
            currentDepth: 0,
            maxDepth: maxDepth,
            minClusterSize: minClusterSize,
            targetClusters: targetClustersPerLevel
        )
        
        return root
    }
    
    private static func recursiveCluster(
        node: HierarchicalClusterNode,
        embeddings: [[Float]],
        currentDepth: Int,
        maxDepth: Int,
        minClusterSize: Int,
        targetClusters: Int
    ) {
        guard currentDepth < maxDepth else { return }
        guard node.memberIndices.count >= minClusterSize * 2 else { return }
        
        // Extract embeddings for this node
        let nodeEmbeddings = node.memberIndices.map { embeddings[$0] }
        
        // Determine k for this level
        let k = min(targetClusters, node.memberIndices.count / minClusterSize)
        guard k >= 2 else { return }
        
        // Cluster
        let config = SphericalKMeansConfiguration.fast(k: k)
        let kmeans = SphericalKMeans(configuration: config)
        let result = kmeans.cluster(nodeEmbeddings)
        
        // Create child nodes
        for cluster in result.nonEmptyClusters {
            guard cluster.size >= minClusterSize else { continue }
            
            let childIndices = cluster.memberIndices.map { node.memberIndices[$0] }
            let child = HierarchicalClusterNode(
                id: "\(node.id)_\(cluster.id)",
                depth: currentDepth + 1,
                memberIndices: childIndices,
                centroid: cluster.centroid
            )
            
            node.children.append(child)
            
            // Recurse
            recursiveCluster(
                node: child,
                embeddings: embeddings,
                currentDepth: currentDepth + 1,
                maxDepth: maxDepth,
                minClusterSize: minClusterSize,
                targetClusters: targetClusters
            )
        }
    }
    
    private static func calculateCentroid(_ embeddings: [[Float]], indices: [Int]) -> [Float] {
        guard !indices.isEmpty, let first = embeddings.first else { return [] }
        
        var centroid = [Float](repeating: 0, count: first.count)
        for idx in indices {
            for d in 0..<centroid.count {
                centroid[d] += embeddings[idx][d]
            }
        }
        
        // Normalize
        let magnitude = sqrt(centroid.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            centroid = centroid.map { $0 / magnitude }
        }
        
        return centroid
    }
}

// MARK: - Hierarchical Cluster Node

final class HierarchicalClusterNode: @unchecked Sendable {
    let id: String
    let depth: Int
    let memberIndices: [Int]
    let centroid: [Float]
    var children: [HierarchicalClusterNode] = []
    
    var isLeaf: Bool { children.isEmpty }
    var size: Int { memberIndices.count }
    
    init(id: String, depth: Int, memberIndices: [Int], centroid: [Float]) {
        self.id = id
        self.depth = depth
        self.memberIndices = memberIndices
        self.centroid = centroid
    }
    
    /// Get all leaf nodes
    func getLeaves() -> [HierarchicalClusterNode] {
        if isLeaf {
            return [self]
        }
        return children.flatMap { $0.getLeaves() }
    }
    
    /// Get nodes at specific depth
    func getNodesAtDepth(_ targetDepth: Int) -> [HierarchicalClusterNode] {
        if depth == targetDepth {
            return [self]
        }
        if depth > targetDepth {
            return []
        }
        return children.flatMap { $0.getNodesAtDepth(targetDepth) }
    }
}

