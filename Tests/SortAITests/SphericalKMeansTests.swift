// MARK: - Spherical K-Means Tests

import XCTest
@testable import SortAI

final class SphericalKMeansTests: XCTestCase {
    
    // MARK: - Basic Clustering
    
    func testBasicClustering() {
        let embeddings: [[Float]] = [
            [1.0, 0.0, 0.0],
            [0.98, 0.02, 0.0],
            [0.0, 1.0, 0.0],
            [0.02, 0.98, 0.0],
            [0.0, 0.0, 1.0],
            [0.0, 0.02, 0.98]
        ]
        
        let config = SphericalKMeansConfiguration.default(k: 3)
        let kmeans = SphericalKMeans(configuration: config)
        let result = kmeans.cluster(embeddings)
        
        XCTAssertEqual(result.clusters.count, 3)
        XCTAssertEqual(result.assignments.count, 6)
        XCTAssertTrue(result.converged || result.iterations > 0)
    }
    
    func testClusterAssignments() {
        // Create clear clusters
        let embeddings: [[Float]] = [
            [1.0, 0.0],  // Cluster A
            [0.99, 0.01],  // Cluster A
            [0.0, 1.0],  // Cluster B
            [0.01, 0.99]  // Cluster B
        ]
        
        let config = SphericalKMeansConfiguration.default(k: 2)
        let kmeans = SphericalKMeans(configuration: config)
        let result = kmeans.cluster(embeddings)
        
        // Points 0,1 should be in same cluster; points 2,3 should be in same cluster
        XCTAssertEqual(result.assignments[0], result.assignments[1])
        XCTAssertEqual(result.assignments[2], result.assignments[3])
        XCTAssertNotEqual(result.assignments[0], result.assignments[2])
    }
    
    func testEmptyInput() {
        let config = SphericalKMeansConfiguration.default(k: 3)
        let kmeans = SphericalKMeans(configuration: config)
        let result = kmeans.cluster([])
        
        XCTAssertTrue(result.clusters.isEmpty)
        XCTAssertTrue(result.assignments.isEmpty)
        XCTAssertTrue(result.converged)
    }
    
    func testFewerPointsThanClusters() {
        let embeddings: [[Float]] = [
            [1.0, 0.0],
            [0.0, 1.0]
        ]
        
        let config = SphericalKMeansConfiguration.default(k: 5)
        let kmeans = SphericalKMeans(configuration: config)
        let result = kmeans.cluster(embeddings)
        
        // Each point becomes its own cluster
        XCTAssertEqual(result.clusters.count, 2)
        XCTAssertEqual(result.assignments.count, 2)
    }
    
    // MARK: - Cluster Quality
    
    func testClusterCohesion() {
        let embeddings: [[Float]] = [
            [1.0, 0.0, 0.0],
            [0.95, 0.05, 0.0],
            [0.90, 0.10, 0.0]
        ]
        
        let config = SphericalKMeansConfiguration.default(k: 1)
        let kmeans = SphericalKMeans(configuration: config)
        let result = kmeans.cluster(embeddings)
        
        XCTAssertEqual(result.clusters.count, 1)
        
        let cohesion = result.clusters[0].cohesion
        XCTAssertGreaterThan(cohesion, 0.8, "Tight cluster should have high cohesion")
    }
    
    func testClusterSize() {
        let embeddings: [[Float]] = [
            [1.0, 0.0],
            [0.99, 0.01],
            [0.98, 0.02],
            [0.0, 1.0]
        ]
        
        let config = SphericalKMeansConfiguration.default(k: 2)
        let kmeans = SphericalKMeans(configuration: config)
        let result = kmeans.cluster(embeddings)
        
        let sizes = result.clusters.map { $0.size }
        XCTAssertTrue(sizes.contains(3) || sizes.contains(1))
    }
    
    func testNonEmptyClusters() {
        let embeddings: [[Float]] = (0..<20).map { i in
            let angle = Float(i) / 20.0 * 2 * Float.pi
            return [cos(angle), sin(angle)]
        }
        
        let config = SphericalKMeansConfiguration.default(k: 4)
        let kmeans = SphericalKMeans(configuration: config)
        let result = kmeans.cluster(embeddings)
        
        let nonEmpty = result.nonEmptyClusters
        XCTAssertGreaterThanOrEqual(nonEmpty.count, 1)
    }
    
    // MARK: - Convergence
    
    func testConvergence() {
        let embeddings: [[Float]] = [
            [1.0, 0.0],
            [0.0, 1.0],
            [-1.0, 0.0],
            [0.0, -1.0]
        ]
        
        let config = SphericalKMeansConfiguration(
            k: 2,
            maxIterations: 100,
            tolerance: 0.0001,
            nInit: 1,
            minClusterSize: 1,
            randomSeed: 42
        )
        let kmeans = SphericalKMeans(configuration: config)
        let result = kmeans.cluster(embeddings)
        
        XCTAssertTrue(result.converged || result.iterations == 100)
    }
    
    func testReproducibilityWithSeed() {
        let embeddings: [[Float]] = (0..<10).map { _ in
            [Float.random(in: -1...1), Float.random(in: -1...1)]
        }
        
        let config = SphericalKMeansConfiguration(
            k: 3,
            maxIterations: 50,
            tolerance: 0.001,
            nInit: 1,
            minClusterSize: 1,
            randomSeed: 12345
        )
        
        let kmeans = SphericalKMeans(configuration: config)
        let result1 = kmeans.cluster(embeddings)
        let result2 = kmeans.cluster(embeddings)
        
        XCTAssertEqual(result1.assignments, result2.assignments)
    }
    
    // MARK: - Configuration Tests
    
    func testFastConfiguration() {
        let config = SphericalKMeansConfiguration.fast(k: 3)
        
        XCTAssertEqual(config.k, 3)
        XCTAssertEqual(config.maxIterations, 50)
        XCTAssertEqual(config.nInit, 1)
    }
    
    func testDefaultConfiguration() {
        let config = SphericalKMeansConfiguration.default(k: 5)
        
        XCTAssertEqual(config.k, 5)
        XCTAssertEqual(config.maxIterations, 100)
        XCTAssertEqual(config.nInit, 3)
    }
    
    // MARK: - Elbow Method
    
    func testFindOptimalK() {
        // Create data with 3 natural clusters
        var embeddings: [[Float]] = []
        for _ in 0..<10 {
            embeddings.append([1.0 + Float.random(in: -0.1...0.1), 0.0 + Float.random(in: -0.1...0.1)])
        }
        for _ in 0..<10 {
            embeddings.append([0.0 + Float.random(in: -0.1...0.1), 1.0 + Float.random(in: -0.1...0.1)])
        }
        for _ in 0..<10 {
            embeddings.append([-1.0 + Float.random(in: -0.1...0.1), 0.0 + Float.random(in: -0.1...0.1)])
        }
        
        let (optimalK, inertias) = SphericalKMeans.findOptimalK(
            embeddings: embeddings,
            kRange: 2...6
        )
        
        XCTAssertGreaterThanOrEqual(optimalK, 2)
        XCTAssertLessThanOrEqual(optimalK, 6)
        XCTAssertEqual(inertias.count, 5)
    }
    
    // MARK: - Hierarchical Clustering
    
    func testHierarchicalCluster() {
        let embeddings: [[Float]] = (0..<20).map { i in
            let angle = Float(i) / 20.0 * 2 * Float.pi
            return [cos(angle), sin(angle)]
        }
        
        let root = SphericalKMeans.hierarchicalCluster(
            embeddings: embeddings,
            maxDepth: 2,
            minClusterSize: 3,
            targetClustersPerLevel: 3
        )
        
        XCTAssertEqual(root.depth, 0)
        XCTAssertEqual(root.memberIndices.count, 20)
    }
    
    func testHierarchicalClusterDepth() {
        let embeddings: [[Float]] = (0..<100).map { i in
            let angle = Float(i) / 100.0 * 2 * Float.pi
            return [cos(angle), sin(angle)]
        }
        
        let root = SphericalKMeans.hierarchicalCluster(
            embeddings: embeddings,
            maxDepth: 3,
            minClusterSize: 5,
            targetClustersPerLevel: 4
        )
        
        // Check tree structure
        XCTAssertFalse(root.isLeaf)
        XCTAssertGreaterThan(root.children.count, 0)
        
        // Get all leaves
        let leaves = root.getLeaves()
        XCTAssertGreaterThan(leaves.count, 0)
    }
    
    func testGetNodesAtDepth() {
        let embeddings: [[Float]] = (0..<50).map { i in
            let angle = Float(i) / 50.0 * 2 * Float.pi
            return [cos(angle), sin(angle)]
        }
        
        let root = SphericalKMeans.hierarchicalCluster(
            embeddings: embeddings,
            maxDepth: 2,
            minClusterSize: 5,
            targetClustersPerLevel: 3
        )
        
        let depth0 = root.getNodesAtDepth(0)
        let depth1 = root.getNodesAtDepth(1)
        
        XCTAssertEqual(depth0.count, 1)
        XCTAssertGreaterThanOrEqual(depth1.count, 0)
    }
    
    // MARK: - SphericalCluster Tests
    
    func testSphericalClusterProperties() {
        let cluster = SphericalCluster(
            id: 0,
            centroid: [1.0, 0.0, 0.0],
            memberIndices: [0, 1, 2],
            memberSimilarities: [0.95, 0.90, 0.85]
        )
        
        XCTAssertEqual(cluster.id, 0)
        XCTAssertEqual(cluster.size, 3)
        XCTAssertEqual(cluster.cohesion, 0.9, accuracy: 0.01)
        XCTAssertGreaterThan(cluster.variance, 0)
    }
    
    func testEmptyCluster() {
        let cluster = SphericalCluster(
            id: 0,
            centroid: [1.0, 0.0, 0.0],
            memberIndices: [],
            memberSimilarities: []
        )
        
        XCTAssertEqual(cluster.size, 0)
        XCTAssertEqual(cluster.cohesion, 0)
        XCTAssertEqual(cluster.variance, 0)
    }
    
    func testSingleMemberCluster() {
        let cluster = SphericalCluster(
            id: 0,
            centroid: [1.0, 0.0, 0.0],
            memberIndices: [0],
            memberSimilarities: [1.0]
        )
        
        XCTAssertEqual(cluster.size, 1)
        XCTAssertEqual(cluster.cohesion, 1.0)
        XCTAssertEqual(cluster.variance, 0)  // No variance with single member
    }
    
    // MARK: - HierarchicalClusterNode Tests
    
    func testHierarchicalClusterNode() {
        let node = HierarchicalClusterNode(
            id: "test",
            depth: 1,
            memberIndices: [0, 1, 2],
            centroid: [1.0, 0.0]
        )
        
        XCTAssertEqual(node.id, "test")
        XCTAssertEqual(node.depth, 1)
        XCTAssertEqual(node.size, 3)
        XCTAssertTrue(node.isLeaf)
    }
    
    func testHierarchicalClusterNodeWithChildren() {
        let parent = HierarchicalClusterNode(
            id: "parent",
            depth: 0,
            memberIndices: [0, 1, 2, 3],
            centroid: [0.5, 0.5]
        )
        
        let child1 = HierarchicalClusterNode(
            id: "child1",
            depth: 1,
            memberIndices: [0, 1],
            centroid: [1.0, 0.0]
        )
        
        let child2 = HierarchicalClusterNode(
            id: "child2",
            depth: 1,
            memberIndices: [2, 3],
            centroid: [0.0, 1.0]
        )
        
        parent.children = [child1, child2]
        
        XCTAssertFalse(parent.isLeaf)
        XCTAssertEqual(parent.children.count, 2)
        XCTAssertTrue(child1.isLeaf)
    }
}

// MARK: - SphericalKMeansResult Tests

final class SphericalKMeansResultTests: XCTestCase {
    
    func testAverageCohesion() {
        let clusters = [
            SphericalCluster(id: 0, centroid: [], memberIndices: [0], memberSimilarities: [0.9]),
            SphericalCluster(id: 1, centroid: [], memberIndices: [1], memberSimilarities: [0.8]),
            SphericalCluster(id: 2, centroid: [], memberIndices: [], memberSimilarities: [])  // Empty
        ]
        
        let result = SphericalKMeansResult(
            clusters: clusters,
            assignments: [0, 1],
            iterations: 10,
            converged: true
        )
        
        XCTAssertEqual(result.averageCohesion, 0.85, accuracy: 0.01)
    }
    
    func testNonEmptyClustersFilter() {
        let clusters = [
            SphericalCluster(id: 0, centroid: [], memberIndices: [0], memberSimilarities: [0.9]),
            SphericalCluster(id: 1, centroid: [], memberIndices: [], memberSimilarities: []),  // Empty
            SphericalCluster(id: 2, centroid: [], memberIndices: [1], memberSimilarities: [0.8])
        ]
        
        let result = SphericalKMeansResult(
            clusters: clusters,
            assignments: [0, 2],
            iterations: 5,
            converged: true
        )
        
        XCTAssertEqual(result.nonEmptyClusters.count, 2)
    }
}
