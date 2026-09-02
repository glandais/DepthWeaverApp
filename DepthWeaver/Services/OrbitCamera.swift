import Foundation
import SceneKit
import simd

/// Spherical camera framing for the canvas' live mode.
///
/// `Model3DCaptureView` hands the orbiting to SceneKit's own camera controller,
/// which is fine for a viewport you can see. Live mode has no viewport — the
/// scene is rendered straight into a depth buffer — so the framing has to be a
/// value the canvas can drive from raw gesture deltas, clamp, and reset.
///
/// Everything is expressed in units of `extent`, the longest side of the
/// content's bounding box, so a 2 cm figurine and a 40 m building orbit and
/// dolly at the same feel.
struct OrbitCamera: Equatable {
    var target = SIMD3<Float>(repeating: 0)
    var distance: Float = 2.5
    /// Radians, counted from the +Z axis towards +X.
    var azimuth: Float = 0
    /// Radians above the horizon, clamped short of the poles where the up
    /// vector degenerates.
    var elevation: Float = 0
    var extent: Float = 1
    var fieldOfView: Float = 50

    /// Radians per point of drag — a full-width swipe turns the model roughly
    /// half a revolution.
    static let rotationSpeed: Float = .pi / 400
    static let maxElevation: Float = .pi / 2 - 0.05

    var minDistance: Float { Swift.max(0.0001, extent * 0.15) }
    var maxDistance: Float { Swift.max(0.001, extent * 20) }
    var zNear: Float { Swift.max(extent * 0.005, distance * 0.02) }
    var zFar: Float { distance + extent * 4 }

    var position: SIMD3<Float> {
        let ce = cos(elevation)
        return target + distance * SIMD3<Float>(ce * sin(azimuth), sin(elevation), ce * cos(azimuth))
    }

    /// Camera basis, derived rather than stored so it always matches `position`.
    private var basis: (right: SIMD3<Float>, up: SIMD3<Float>) {
        let forward = simd_normalize(target - position)
        var right = simd_cross(forward, SIMD3<Float>(0, 1, 0))
        if simd_length(right) < 1e-5 { right = SIMD3<Float>(1, 0, 0) }
        right = simd_normalize(right)
        return (right, simd_normalize(simd_cross(right, forward)))
    }

    // MARK: - Gestures

    /// One-finger drag: the model turns with the finger.
    mutating func rotate(dx: Float, dy: Float) {
        guard dx.isFinite, dy.isFinite else { return }
        azimuth -= dx * Self.rotationSpeed
        elevation = Swift.min(
            Swift.max(elevation + dy * Self.rotationSpeed, -Self.maxElevation),
            Self.maxElevation
        )
    }

    /// Pinch: spreading (factor > 1) moves the camera closer.
    mutating func dolly(by factor: Float) {
        guard factor.isFinite, factor > 0 else { return }
        distance = Swift.min(Swift.max(distance / factor, minDistance), maxDistance)
    }

    /// Two-finger drag: the model slides under the finger. `dx`/`dy` are screen
    /// points (y down, as UIKit reports them) and `viewHeight` the viewport
    /// height they were measured in, so the model tracks the touch exactly.
    mutating func pan(dx: Float, dy: Float, viewHeight: Float) {
        guard dx.isFinite, dy.isFinite, viewHeight > 0 else { return }
        let worldPerPoint = 2 * distance * tan(fieldOfView * .pi / 360) / viewHeight
        let (right, up) = basis
        target += (up * dy - right * dx) * worldPerPoint
    }

    // MARK: - SceneKit

    /// Writes this framing onto a camera node.
    func apply(to node: SCNNode) {
        node.simdPosition = position
        node.simdLook(
            at: target,
            up: SIMD3<Float>(0, 1, 0),
            localFront: SIMD3<Float>(0, 0, -1)
        )
        let camera = node.camera ?? SCNCamera()
        // `pan` converts points to world units through the *vertical* FOV, so
        // pin the projection down instead of leaving it `.automatic`, which
        // would switch to the horizontal axis on a landscape canvas and make
        // the model drift away from the finger.
        camera.projectionDirection = .vertical
        camera.fieldOfView = CGFloat(fieldOfView)
        camera.zNear = Double(zNear)
        camera.zFar = Double(zFar)
        node.camera = camera
    }

    /// Frames a scene the way `Model3DLoader` frames it, then adopts the angle
    /// of whatever camera the scene already carries — so entering live mode
    /// picks up where the 3D capture screen left the model rather than snapping
    /// back to the front.
    static func framing(scene: SCNScene, matching existingCamera: SCNNode? = nil) -> OrbitCamera {
        var orbit = OrbitCamera()
        let bounds = contentBounds(of: scene.rootNode)
        orbit.target = bounds.center
        orbit.extent = bounds.extent
        orbit.distance = bounds.extent * 2.5

        let camera = existingCamera ?? firstCameraNode(in: scene.rootNode)
        if let camera {
            if let fov = camera.camera?.fieldOfView, fov > 1, fov < 170 {
                orbit.fieldOfView = Float(fov)
            }
            let v = camera.simdWorldPosition - orbit.target
            let d = simd_length(v)
            if d > 1e-4 {
                orbit.distance = Swift.min(Swift.max(d, orbit.minDistance), orbit.maxDistance)
                orbit.elevation = asin(Swift.min(Swift.max(v.y / d, -1), 1))
                orbit.elevation = Swift.min(
                    Swift.max(orbit.elevation, -maxElevation),
                    maxElevation
                )
                orbit.azimuth = atan2(v.x, v.z)
            }
        }
        return orbit
    }

    /// Bounding box of the drawable content only. The scene's camera nodes sit
    /// well outside the model, and `SCNNode.boundingBox` on the root would drag
    /// them in and frame a mostly empty box.
    static func contentBounds(of root: SCNNode) -> (center: SIMD3<Float>, extent: Float) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var found = false

        func visit(_ node: SCNNode) {
            if node.geometry != nil {
                let (bmin, bmax) = node.boundingBox
                let xs = [Float(bmin.x), Float(bmax.x)]
                let ys = [Float(bmin.y), Float(bmax.y)]
                let zs = [Float(bmin.z), Float(bmax.z)]
                let m = node.simdWorldTransform
                for x in xs {
                    for y in ys {
                        for z in zs {
                            let p4 = m * SIMD4<Float>(x, y, z, 1)
                            let p = SIMD3<Float>(p4.x, p4.y, p4.z)
                            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { continue }
                            lo = SIMD3<Float>(
                                Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z)
                            )
                            hi = SIMD3<Float>(
                                Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z)
                            )
                            found = true
                        }
                    }
                }
            }
            for child in node.childNodes { visit(child) }
        }
        visit(root)

        guard found else { return (SIMD3<Float>(repeating: 0), 1) }
        let center = (lo + hi) / 2
        let size = hi - lo
        let extent = Swift.max(size.x, Swift.max(size.y, size.z))
        return (center, extent.isFinite && extent > 0.0001 ? extent : 1)
    }

    private static func firstCameraNode(in node: SCNNode) -> SCNNode? {
        if node.camera != nil { return node }
        for child in node.childNodes {
            if let found = firstCameraNode(in: child) { return found }
        }
        return nil
    }
}
