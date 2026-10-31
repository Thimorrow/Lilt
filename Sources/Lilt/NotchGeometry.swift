import Foundation

struct NotchGeometry {
    static let panelSize = CGSize(width: 680, height: 300)
    let screenFrame: CGRect
    let hardwareWidth: CGFloat
    let hardwareHeight: CGFloat

    init(screenFrame: CGRect, safeTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?) {
        self.screenFrame = screenFrame
        let gap = (rightArea?.minX ?? 0) - (leftArea?.maxX ?? 0)
        hardwareWidth = safeTop > 0 && gap > 0 ? min(gap, 300) : 180
        hardwareHeight = safeTop > 0 ? min(safeTop, 64) : 32
    }

    var panelFrame: CGRect {
        CGRect(x: screenFrame.midX - Self.panelSize.width / 2,
               y: screenFrame.maxY - Self.panelSize.height,
               width: Self.panelSize.width, height: Self.panelSize.height)
    }

    func surfaceRect(open: Bool) -> CGRect {
        let width = open ? max(500, hardwareWidth + 260) : hardwareWidth + 132
        let height = open ? hardwareHeight + 160 : hardwareHeight
        return CGRect(x: (Self.panelSize.width - width) / 2, y: 0, width: width, height: height)
    }
}
