import SwiftUI
import ARKit
import SceneKit

// MARK: - Data Model

struct SensorCoverageData: Identifiable, Hashable {
    let id = UUID()
    let ceilingHeightFeet: Float
    let fovWidthFeet: Float
    let fovLengthFeet: Float
}

// MARK: - Main SwiftUI View
struct ContentView: View {
    
    // Example coverage table
    let coverageOptions: [SensorCoverageData] = [
        SensorCoverageData(ceilingHeightFeet: 7.5, fovWidthFeet: 7.7, fovLengthFeet: 9.5),
        SensorCoverageData(ceilingHeightFeet: 8.0, fovWidthFeet: 9.2, fovLengthFeet: 10.7),
        SensorCoverageData(ceilingHeightFeet: 9.0, fovWidthFeet: 10.0, fovLengthFeet: 12.4),
        SensorCoverageData(ceilingHeightFeet: 10.0, fovWidthFeet: 10.7, fovLengthFeet: 13.7),
        SensorCoverageData(ceilingHeightFeet: 11.0, fovWidthFeet: 12.0, fovLengthFeet: 15.2)
    ]
    
    // State: which coverage option is selected?
    @State private var selectedCoverage: SensorCoverageData? = nil
    
    // State: are we using feet (true) or meters (false)?
    @State private var useFeet: Bool = true
    
    var body: some View {
        ZStack {
            // 1) AR view in the background
            ARViewContainer(selectedCoverageData: $selectedCoverage, useFeet: $useFeet)
                .edgesIgnoringSafeArea(.all)
            
            // 2) UI overlay
            VStack {
                Spacer()
                
                // Picker to choose coverage from the table
                Picker("Coverage Options", selection: $selectedCoverage) {
                    ForEach(coverageOptions) { option in
                        Text(
                            String(format: "%.1f ft (W=%.1f, L=%.1f)",
                                   option.ceilingHeightFeet,
                                   option.fovWidthFeet,
                                   option.fovLengthFeet)
                        )
                        .tag(option as SensorCoverageData?)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 100)
                .background(Color.white.opacity(0.8))
                
                // Segmented control to toggle Feet vs. Meters
                HStack {
                    Text("Units:")
                    Picker("Units", selection: $useFeet) {
                        Text("Feet").tag(true)
                        Text("Meters").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .background(Color.white.opacity(0.8))
                }
            }
        }
        .onAppear {
            // Set a default coverage option
            selectedCoverage = coverageOptions.first
        }
    }
}

// MARK: - ARViewContainer (UIViewRepresentable)
struct ARViewContainer: UIViewRepresentable {
    
    // Bindings from SwiftUI
    @Binding var selectedCoverageData: SensorCoverageData?
    @Binding var useFeet: Bool
    
    // Create the Coordinator (manages ARKit logic)
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // Create the ARSCNView
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        
        // Delegate (if we want to respond to ARSCNView events)
        arView.delegate = context.coordinator
        
        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        
        // If device supports LiDAR scene reconstruction
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
            configuration.sceneReconstruction = .mesh
        }
        
        // Run session
        arView.session.run(configuration)
        
        // Add tap gesture to place the sensor coverage shape
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        return arView
    }
    
    // Update the view if SwiftUI state changes (e.g., user picks a new coverage data)
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.updateCoverageIfNeeded()
    }
}

// MARK: - Coordinator
extension ARViewContainer {
    class Coordinator: NSObject, ARSCNViewDelegate {
        
        var parent: ARViewContainer
        
        // Keep references to the AR view and the coverage nodes
        weak var sceneView: ARSCNView?
        var sensorAnchorNode: SCNNode?
        var coverageNode: SCNNode?
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        // Handle taps in the AR view
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView = gesture.view as? ARSCNView else { return }
            self.sceneView = sceneView
            
            let location = gesture.location(in: sceneView)
            
            // Try ARKit's raycast (iOS 13+)
            if let query = sceneView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal) {
                let results = sceneView.session.raycast(query)
                if let result = results.first {
                    let position = SCNVector3(
                        result.worldTransform.columns.3.x,
                        result.worldTransform.columns.3.y,
                        result.worldTransform.columns.3.z
                    )
                    placeSensor(at: position)
                }
            } else {
                // Fallback for older iOS: use hitTest
                let hitResults = sceneView.hitTest(location, types: [.existingPlaneUsingExtent])
                if let hit = hitResults.first {
                    let position = SCNVector3(
                        hit.worldTransform.columns.3.x,
                        hit.worldTransform.columns.3.y,
                        hit.worldTransform.columns.3.z
                    )
                    placeSensor(at: position)
                }
            }
        }
        
        // Place the sensor anchor node at the tapped position
        func placeSensor(at position: SCNVector3) {
            // Remove any old anchor node
            sensorAnchorNode?.removeFromParentNode()
            
            // Create a new anchor node at that position
            let anchorNode = SCNNode()
            anchorNode.position = position
            sceneView?.scene.rootNode.addChildNode(anchorNode)
            sensorAnchorNode = anchorNode
            
            // Create/update the coverage shape
            updateCoverageNode(anchorNode: anchorNode)
        }
        
        // If coverage data changes, update the shape
        func updateCoverageIfNeeded() {
            if let anchorNode = sensorAnchorNode {
                updateCoverageNode(anchorNode: anchorNode)
            }
        }
        
        // Rebuild coverage node
        func updateCoverageNode(anchorNode: SCNNode) {
            // Remove old coverage node
            coverageNode?.removeFromParentNode()
            guard let coverageData = parent.selectedCoverageData else { return }
            
            // Create new coverage node
            let newNode = createCoverageNode(for: coverageData, inFeet: parent.useFeet)
            coverageNode = newNode
            anchorNode.addChildNode(newNode)
            
            // Shift coverage so the apex is at the anchor (the ceiling)
            let shiftY = (parent.useFeet
                          ? feetToMeters(coverageData.ceilingHeightFeet)
                          : coverageData.ceilingHeightFeet) / 2.0
            newNode.position = SCNVector3(0, -shiftY, 0)
        }
        
        // Build the cone geometry for coverage
        func createCoverageNode(for coverageData: SensorCoverageData, inFeet: Bool) -> SCNNode {
            let coneGeometry = SCNCone(topRadius: 0, bottomRadius: 1, height: 1)
            coneGeometry.firstMaterial?.diffuse.contents = UIColor.red.withAlphaComponent(0.3)
            coneGeometry.firstMaterial?.isDoubleSided = true
            
            let coneNode = SCNNode(geometry: coneGeometry)
            
            let height = coverageData.ceilingHeightFeet
            let baseWidth = coverageData.fovWidthFeet
            let baseLength = coverageData.fovLengthFeet
            
            // Convert to meters if needed
            let heightMeters = inFeet ? feetToMeters(height) : height
            let baseWidthMeters = inFeet ? feetToMeters(baseWidth) : baseWidth
            let baseLengthMeters = inFeet ? feetToMeters(baseLength) : baseLength
            
            // Scale the cone to represent coverage footprint
            // X scale = half coverage width, Y = sensor height, Z = half coverage length
            coneNode.scale = SCNVector3(
                baseWidthMeters / 2.0,
                heightMeters,
                baseLengthMeters / 2.0
            )
            
            return coneNode
        }
        
        // Convert feet to meters
        func feetToMeters(_ feet: Float) -> Float {
            return feet * 0.3048
        }
    }
}

