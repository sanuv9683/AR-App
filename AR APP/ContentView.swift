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
            // AR view in the background
            ARViewContainer(selectedCoverageData: $selectedCoverage, useFeet: $useFeet)
                .edgesIgnoringSafeArea(.all)
            
            // UI overlay
            VStack {
                Spacer()
                
                // Coverage Picker Card
                VStack(spacing: 8) {
                    Text("Select Coverage")
                        .font(.headline)
                    
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
                    .clipped()
                }
                .padding()
                .background(Color.white.opacity(0.9))
                .cornerRadius(12)
                .shadow(radius: 5)
                .padding(.bottom, 20)
                
                // Units Picker Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Units")
                        .font(.headline)
                    
                    Picker("Units", selection: $useFeet) {
                        Text("Feet").tag(true)
                        Text("Meters").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .tint(.blue) // iOS 15+ accent color for segmented picker
                }
                .padding()
                .background(Color.white.opacity(0.9))
                .cornerRadius(10)
                .shadow(radius: 2)
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Set a default coverage option when view appears
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
        
        // Set delegate to coordinator
        arView.delegate = context.coordinator
        
        // Configure AR session with horizontal plane detection
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        
        // If the device supports LiDAR scene reconstruction, enable it
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
            configuration.sceneReconstruction = .mesh
        }
        
        // Run AR session
        arView.session.run(configuration)
        
        // Add tap gesture recognizer to place the sensor
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        return arView
    }
    
    // Update the ARSCNView if SwiftUI state changes
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.updateCoverageIfNeeded()
    }
}

// MARK: - Coordinator

extension ARViewContainer {
    class Coordinator: NSObject, ARSCNViewDelegate {
        
        var parent: ARViewContainer
        
        // Keep references to the AR view and nodes
        weak var sceneView: ARSCNView?
        var sensorAnchorNode: SCNNode?
        var coverageNode: SCNNode?
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        // Handle tap gestures in the AR view
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView = gesture.view as? ARSCNView else { return }
            self.sceneView = sceneView
            
            let location = gesture.location(in: sceneView)
            
            // Use ARKit's raycast (iOS 13+) to find a horizontal plane
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
                // Fallback for older iOS versions using hitTest
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
            // Remove any previous sensor anchor
            sensorAnchorNode?.removeFromParentNode()
            
            // Create a new anchor node
            let anchorNode = SCNNode()
            anchorNode.position = position
            sceneView?.scene.rootNode.addChildNode(anchorNode)
            sensorAnchorNode = anchorNode
            
            // Create or update the coverage shape
            updateCoverageNode(anchorNode: anchorNode)
        }
        
        // Update the coverage shape if the data changes
        func updateCoverageIfNeeded() {
            if let anchorNode = sensorAnchorNode {
                updateCoverageNode(anchorNode: anchorNode)
            }
        }
        
        // Rebuild the coverage node and attach it to the anchor
        func updateCoverageNode(anchorNode: SCNNode) {
            coverageNode?.removeFromParentNode()
            guard let coverageData = parent.selectedCoverageData else { return }
            
            let newNode = createCoverageNode(for: coverageData, inFeet: parent.useFeet)
            coverageNode = newNode
            anchorNode.addChildNode(newNode)
            
            // Adjust position so the apex is at the sensor anchor
            let shiftY = (parent.useFeet
                          ? feetToMeters(coverageData.ceilingHeightFeet)
                          : coverageData.ceilingHeightFeet) / 2.0
            newNode.position = SCNVector3(0, -shiftY, 0)
        }
        
        // Build the AR geometry (a cone that looks like a blue laser beam)
        func createCoverageNode(for coverageData: SensorCoverageData, inFeet: Bool) -> SCNNode {
            let coneGeometry = SCNCone(topRadius: 0, bottomRadius: 1, height: 1)
            // Set the diffuse color to a bright blue with slight transparency
            coneGeometry.firstMaterial?.diffuse.contents = UIColor.blue.withAlphaComponent(0.6)
            // Make both sides visible
            coneGeometry.firstMaterial?.isDoubleSided = true
            // Add emission to create a laser-like glow effect
            coneGeometry.firstMaterial?.emission.contents = UIColor.cyan
            coneGeometry.firstMaterial?.emission.intensity = 1.0
            
            let coneNode = SCNNode(geometry: coneGeometry)
            
            let height = coverageData.ceilingHeightFeet
            let baseWidth = coverageData.fovWidthFeet
            let baseLength = coverageData.fovLengthFeet
            
            // Convert dimensions to meters if needed
            let heightMeters = inFeet ? feetToMeters(height) : height
            let baseWidthMeters = inFeet ? feetToMeters(baseWidth) : baseWidth
            let baseLengthMeters = inFeet ? feetToMeters(baseLength) : baseLength
            
            // Scale the cone:
            // X scale: half the coverage width
            // Y scale: the ceiling height (vertical beam length)
            // Z scale: half the coverage length
            coneNode.scale = SCNVector3(
                baseWidthMeters / 2.0,
                heightMeters,
                baseLengthMeters / 2.0
            )
            
            return coneNode
        }
        
        // Helper: Convert feet to meters
        func feetToMeters(_ feet: Float) -> Float {
            return feet * 0.3048
        }
    }
}
