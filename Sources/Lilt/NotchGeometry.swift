import Foundation

struct NotchGeometry {
    static let panelSize = CGSize(width: 680, height: 300)
    let screenFrame: CGRect
    let hardwareWidth: CGFloat
    let hardwareHeight: CGFloat
    let hideHardwareWings: Bool
    let hideNotchContent: Bool

    init(screenFrame: CGRect, safeTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?) {
        self.screenFrame = screenFrame
        let validTop = safeTop.isFinite && safeTop > 0
        if validTop, let leftArea, let rightArea,
           leftArea.minX.isFinite, leftArea.maxX.isFinite, leftArea.width > 0,
           rightArea.minX.isFinite, rightArea.maxX.isFinite, rightArea.width > 0 {
            let gap = rightArea.minX - leftArea.maxX
            let center = (rightArea.minX + leftArea.maxX) / 2
            let offset = min(abs(center - screenFrame.midX), abs(center - screenFrame.width / 2))
            let centered = offset <= 24
            let validGap = gap.isFinite && gap > 0 && centered
            let protectedWidth = gap + 2 * offset
            hardwareWidth = validGap ? min(protectedWidth, 500) : 180
            hideHardwareWings = !validGap || protectedWidth > 500
        } else {
            hardwareWidth = 180
            hideHardwareWings = !safeTop.isFinite || safeTop > 0
        }
        hardwareHeight = validTop ? max(24, min(safeTop, 100)) : 32
        hideNotchContent = !safeTop.isFinite || safeTop > 100
    }

    var panelFrame: CGRect {
        CGRect(x: screenFrame.midX - Self.panelSize.width / 2,
               y: screenFrame.maxY - Self.panelSize.height,
               width: Self.panelSize.width, height: Self.panelSize.height)
    }

    func surfaceRect(open: Bool) -> CGRect {
        let width = open ? min(Self.panelSize.width - 32, max(500, hardwareWidth + 260)) : hardwareWidth + 132
        let height = open ? hardwareHeight + 160 : hardwareHeight
        return CGRect(x: (Self.panelSize.width - width) / 2, y: 0, width: width, height: height)
    }
}
