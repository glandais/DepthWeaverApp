import SceneKit
import SwiftUI

struct DepthPointCloudView: UIViewRepresentable {
    let depthMap: DepthMap
    let adjustment: DepthAdjustment

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false

        let scene = SCNScene()
        view.scene = scene

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 100
        cameraNode.position = SCNVector3(0, 0, 1.4)
        scene.rootNode.addChildNode(cameraNode)

        let pointsNode = SCNNode()
        pointsNode.name = "points"
        scene.rootNode.addChildNode(pointsNode)

        context.coordinator.rebuild(node: pointsNode, depthMap: depthMap, adjustment: adjustment)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let node = uiView.scene?.rootNode.childNode(withName: "points", recursively: false) else { return }
        context.coordinator.rebuild(node: node, depthMap: depthMap, adjustment: adjustment)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var lastKey: String = ""

        func rebuild(node: SCNNode, depthMap: DepthMap, adjustment: DepthAdjustment) {
            let d = depthMap.denoising
            let key = "\(depthMap.id.uuidString)|\(adjustment.min)|\(adjustment.max)|\(adjustment.start)|\(adjustment.end)|\(d.enabled)|\(d.bilateralIntensity)|\(d.morphologyRadius)|\(d.backgroundThreshold)"
            if key == lastKey { return }
            lastKey = key

            let geometry = Self.makeGeometry(depthMap: depthMap, adjustment: adjustment)
            node.geometry = geometry
        }

        private static func makeGeometry(depthMap: DepthMap, adjustment: DepthAdjustment) -> SCNGeometry {
            // Target resolution: full if <= 250k points, else stride 2
            let totalFull = depthMap.width * depthMap.height
            let stride = totalFull > 250_000 ? 2 : 1
            let w = depthMap.width / stride
            let h = depthMap.height / stride

            var adjustedMap = depthMap
            adjustedMap.adjustment = adjustment
            // Sample at reduced grid by asking for full size then striding — simpler: use w,h directly
            let depthValues = adjustedMap.adjustedDepthValues(width: w, height: h)

            let aspect = Float(depthMap.width) / Float(depthMap.height)
            let halfW: Float = aspect >= 1 ? 0.5 : 0.5 * aspect
            let halfH: Float = aspect >= 1 ? 0.5 / aspect : 0.5
            let depthScale: Float = 0.5

            let count = w * h
            var positions = [SCNVector3](); positions.reserveCapacity(count)
            var colors = [SIMD4<Float>](); colors.reserveCapacity(count)

            for y in 0..<h {
                let vY: Float = h > 1 ? Float(y) / Float(h - 1) : 0.5
                let py: Float = (0.5 - vY) * 2 * halfH
                for x in 0..<w {
                    let vX: Float = w > 1 ? Float(x) / Float(w - 1) : 0.5
                    let px: Float = (vX - 0.5) * 2 * halfW
                    let d = depthValues[y * w + x]
                    let pz: Float = d * depthScale
                    positions.append(SCNVector3(px, py, pz))

                    let (r, g, b) = DepthMap.hueColor(forNormalized: d, highlightClamped: false)
                    colors.append(SIMD4<Float>(Float(r), Float(g), Float(b), 1))
                }
            }

            let positionSource = SCNGeometrySource(vertices: positions)

            let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            let colorSource = SCNGeometrySource(
                data: colorData,
                semantic: .color,
                vectorCount: count,
                usesFloatComponents: true,
                componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<SIMD4<Float>>.size
            )

            var indices = [Int32](); indices.reserveCapacity(count)
            for i in 0..<count { indices.append(Int32(i)) }
            let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .point,
                primitiveCount: count,
                bytesPerIndex: MemoryLayout<Int32>.size
            )
            element.pointSize = 4
            element.minimumPointScreenSpaceRadius = 1
            element.maximumPointScreenSpaceRadius = 6

            let geometry = SCNGeometry(sources: [positionSource, colorSource], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.isDoubleSided = true
            geometry.firstMaterial = material
            return geometry
        }
    }
}
