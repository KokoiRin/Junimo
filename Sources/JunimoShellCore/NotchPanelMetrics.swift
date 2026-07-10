import Foundation

public enum NotchPanelMetrics {
    public static let minimumCollapsedHeight: CGFloat = 28

    public static func collapsedHeight(screenTop: CGFloat, visibleTop: CGFloat) -> CGFloat {
        max(minimumCollapsedHeight, screenTop - visibleTop)
    }
}
