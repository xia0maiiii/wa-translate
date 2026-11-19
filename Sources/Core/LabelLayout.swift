import CoreGraphics

/// 译文标签摆在哪：每条译文贴在对应气泡的右侧，始终落在看得见的范围里。
enum LabelLayout {
    static let minimumWidth: CGFloat = 180
    static let maximumWidth: CGFloat = 560
    /// 气泡再矮，译文也至少给这么高（约七行）。
    static let minimumHeight: CGFloat = 120

    /// - Parameters:
    ///   - bubbles: 气泡在屏幕上的位置，自上而下。
    ///   - area: 聊天区看得见的那一段。
    ///   - measure: 第几条译文在给定的最大宽高内实际占多大。
    /// - Returns: 各标签的位置，原点在 `area` 的左上角。
    static func frames(bubbles: [CGRect], area: CGRect, measure: (Int, CGSize) -> CGSize) -> [CGRect] {
        var floor = -CGFloat.infinity
        return bubbles.enumerated().map { index, bubble in
            // 气泡可能有一截滚出了可见范围：译文跟着看得见的那一截走，高度也以它为限。
            let top = max(bubble.minY, area.minY)
            let bottom = min(bubble.maxY, area.maxY)
            let room = area.maxX - bubble.maxX - 20
            let limit = CGSize(width: min(max(room, minimumWidth), maximumWidth), height: max(bottom - top, minimumHeight))
            let size = measure(index, limit)
            // 右边够宽就贴着气泡放，否则靠聊天区右边缘。
            let x = room >= minimumWidth ? bubble.maxX + 8 : area.maxX - size.width - 12
            // 不压住上一条译文；在此前提下尽量不伸出可见范围的下沿。
            let y = max(floor + 3, min(top - area.minY, area.height - size.height - 4))
            floor = y + size.height
            return CGRect(x: x - area.minX, y: y, width: size.width, height: size.height)
        }
    }
}
