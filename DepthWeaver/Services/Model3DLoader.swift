import CoreGraphics
import ModelIO
import os
import SceneKit
import SceneKit.ModelIO

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "Model3DLoader")

enum Model3DLoaderError: Error {
    case unsupportedExtension(String)
    case loadFailed(String)
}

enum Model3DLoader {
    /// File extensions accepted (lowercase, no dot).
    static let acceptedExtensions: Set<String> = ["usdz", "usd", "usda", "usdc", "obj", "scn"]

    static func loadScene(from url: URL) throws -> SCNScene {
        let ext = url.pathExtension.lowercased()
        guard acceptedExtensions.contains(ext) else {
            throw Model3DLoaderError.unsupportedExtension(ext)
        }

        let scene: SCNScene
        do {
            if ext == "scn" {
                scene = try SCNScene(url: url, options: nil)
            } else {
                let asset = MDLAsset(url: url)
                asset.loadTextures()
                scene = SCNScene(mdlAsset: asset)
            }
        } catch {
            logger.error("Failed to load scene: \(error.localizedDescription)")
            throw Model3DLoaderError.loadFailed(error.localizedDescription)
        }

        scene.background.contents = CGColor(gray: 0, alpha: 1)
        frameScene(scene)
        return scene
    }

    /// Adds a perspective camera framed to the scene's bounding box if the scene
    /// has no camera, and adds a default ambient light if it has no lights.
    /// SCNView's `autoenablesDefaultLighting` covers the fallback either way, but
    /// we still need a camera for the renderer to use.
    static func frameScene(_ scene: SCNScene) {
        let root = scene.rootNode

        let hasCamera = root.childNode(withName: "captureCamera", recursively: true) != nil
            || hasCameraInTree(root)
        if !hasCamera {
            let (minBounds, maxBounds) = root.boundingBox
            let cx = Float(minBounds.x + maxBounds.x) / 2
            let cy = Float(minBounds.y + maxBounds.y) / 2
            let cz = Float(minBounds.z + maxBounds.z) / 2
            let dx = Float(maxBounds.x - minBounds.x)
            let dy = Float(maxBounds.y - minBounds.y)
            let dz = Float(maxBounds.z - minBounds.z)
            let extent = max(dx, max(dy, dz))
            let safeExtent: Float = extent.isFinite && extent > 0.0001 ? extent : 1.0
            let distance = safeExtent * 2.5

            let camera = SCNCamera()
            camera.zNear = Double(safeExtent) * 0.05
            camera.zFar = Double(safeExtent) * 20.0
            camera.fieldOfView = 50

            let cameraNode = SCNNode()
            cameraNode.name = "captureCamera"
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(cx, cy, cz + distance)
            cameraNode.look(at: SCNVector3(cx, cy, cz))
            root.addChildNode(cameraNode)
        }
    }

    private static func hasCameraInTree(_ node: SCNNode) -> Bool {
        if node.camera != nil { return true }
        for child in node.childNodes where hasCameraInTree(child) {
            return true
        }
        return false
    }
}
