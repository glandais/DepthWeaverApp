#if os(iOS)
import CoreGraphics
import os
import SceneKit

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "LiveSceneViewModel")

/// Drives the 3D half of the canvas' live mode: it owns the orbit framing, the
/// camera node it writes that framing onto, and the offscreen depth-capture
/// session the gestures feed.
///
/// Nothing here is ever displayed. The scene exists only to be rendered into a
/// depth buffer, once per gesture frame, so the stereogram can be regenerated
/// for the new point of view.
@MainActor
final class LiveSceneViewModel: ObservableObject {
    /// The canvas reads this to decide whether a gesture should orbit a model
    /// or pan a flat depth map.
    @Published private(set) var hasScene = false
    /// True while the framing still matches the one live mode started from,
    /// so the canvas can hide its reset affordance when there is nothing to
    /// reset.
    @Published private(set) var isHome = true

    private(set) var orbit = OrbitCamera()
    private var home = OrbitCamera()
    /// Held strongly: `AppState` owns the scene, but a model swapped out from
    /// under us mid-gesture would otherwise leave `hasScene` lying.
    private var scene: SCNScene?
    private var cameraNode: SCNNode?
    private var session: Model3DDepthRenderer.Session?

    private static let cameraNodeName = "liveOrbitCamera"

    /// Adopts a scene (or drops the current one). Framing is taken from the
    /// scene's own camera, so entering live mode picks up the angle the 3D
    /// capture screen was left at instead of snapping back to the front.
    func attach(scene newScene: SCNScene?) {
        guard newScene !== scene else { return }
        removeCameraNode(from: scene)
        scene = newScene
        hasScene = newScene != nil

        guard let newScene else {
            session = nil
            isHome = true
            return
        }

        // The incoming scene may still carry a node a previous view model left
        // behind; strip it *before* framing, so the angle is read from the
        // model's own camera rather than a stale live one.
        removeCameraNode(from: newScene)

        orbit = OrbitCamera.framing(scene: newScene)
        home = orbit
        isHome = true

        let node = SCNNode()
        node.name = Self.cameraNodeName
        newScene.rootNode.addChildNode(node)
        orbit.apply(to: node)
        cameraNode = node

        if session == nil {
            session = Model3DDepthRenderer.Session()
            if session == nil { logger.error("attach: no Metal session, live 3D unavailable") }
        }
    }

    func reset() {
        orbit = home
        syncCamera()
    }

    // MARK: - Gestures

    func rotate(dx: CGFloat, dy: CGFloat) {
        orbit.rotate(dx: Float(dx), dy: Float(dy))
        syncCamera()
    }

    func pan(dx: CGFloat, dy: CGFloat, viewHeight: CGFloat) {
        orbit.pan(dx: Float(dx), dy: Float(dy), viewHeight: Float(viewHeight))
        syncCamera()
    }

    func zoom(by factor: CGFloat) {
        orbit.dolly(by: Float(factor))
        syncCamera()
    }

    // MARK: - Capture

    /// Renders the current framing into a depth map. Returns nil when there is
    /// no scene, no Metal device, or the render failed — the canvas then falls
    /// back to moving the depth map it already has.
    func captureDepth(size: CGSize) -> DepthMap? {
        guard let scene, let cameraNode, size.width >= 1, size.height >= 1 else { return nil }
        if session == nil { session = Model3DDepthRenderer.Session() }
        guard let session else { return nil }
        return session.captureDepthMap(scene: scene, pointOfView: cameraNode, outputSize: size)
    }

    // MARK: - Private

    private func syncCamera() {
        if isHome != (orbit == home) { isHome = orbit == home }
        guard let cameraNode else { return }
        orbit.apply(to: cameraNode)
    }

    /// Drops our camera node and any namesake a previous view model left in
    /// `target` — the scene outlives us in `AppState`, so a leftover camera
    /// would be picked up as the model's own framing on the next attach.
    private func removeCameraNode(from target: SCNScene?) {
        cameraNode?.removeFromParentNode()
        cameraNode = nil
        while let stale = target?.rootNode.childNode(withName: Self.cameraNodeName, recursively: true) {
            stale.removeFromParentNode()
        }
    }
}
#endif
