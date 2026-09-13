import AppKit
import ApplicationServices

// 只解释触控板事件：一个 Command 横滑最多产生一次方向，惯性只消费、不重复触发。
struct AppBarSwipeRecognizer {
    private var captured = false
    private var decided = true
    private var fired = false
    private var travel: CGFloat = 0

    mutating func handle(_ event: NSEvent, enabled: Bool) -> (consume: Bool, direction: Int?) {
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            self = Self()
        }
        if !event.momentumPhase.isEmpty {
            let consume = captured
            if event.momentumPhase.contains(.ended) { self = Self() }
            return (consume, nil)
        }
        // 普通鼠标滚轮没有手势阶段；也不在普通滚动中途按下 Command 时接管。
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            decided = !enabled || !event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas
        }
        guard !event.phase.isEmpty else { return (false, nil) }
        if !enabled || !event.modifierFlags.contains(.command) {
            decided = true
            fired = true
            return (captured, nil)
        }
        if !decided && (event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0) {
            captured = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            decided = true
        }
        guard captured else { return (false, nil) }
        guard !fired, !event.phase.contains(.cancelled), !event.phase.contains(.ended) else {
            return (true, nil)
        }
        // 消除“自然滚动”偏好对手指左右方向的影响。
        travel += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        guard abs(travel) >= 24 else { return (true, nil) }
        fired = true
        return (true, travel > 0 ? 1 : -1)
    }
}

// 系统权限和事件过滤的边界可替换，测试不读取或修改真实辅助功能授权。
@MainActor
protocol AppBarSwipeAccess: AnyObject {
    func isTrusted(prompt: Bool) -> Bool
    var isRunning: Bool { get }
    func install(handler: @escaping (NSEvent) -> Bool) -> Bool
    func remove()
}

enum AppBarSwipeStatus: Equatable {
    case stopped, needsPermission, unavailable, ready
}

@MainActor
final class AppBarSwipeMonitor {
    private(set) var status: AppBarSwipeStatus = .stopped
    private let access: AppBarSwipeAccess
    private var recognizer = AppBarSwipeRecognizer()
    var canSwitch: () -> Bool = { false }
    var switchDirection: (Int) -> Void = { _ in }
    var isRunning: Bool { status == .ready && access.isRunning }

    init(access: AppBarSwipeAccess? = nil) {
        self.access = access ?? SystemAppBarSwipeAccess()
    }

    func start(prompt: Bool = false) {
        guard access.isTrusted(prompt: prompt) else {
            access.remove()
            recognizer = AppBarSwipeRecognizer()
            status = .needsPermission
            return
        }
        if access.isRunning { status = .ready; return }
        // 睡眠、超时或授权变化可能留下失效的 tap，不能仅因引用存在就放弃重连。
        access.remove()
        recognizer = AppBarSwipeRecognizer()
        let installed = access.install { [weak self] input in
            guard let self else { return false }
            let result = recognizer.handle(input, enabled: canSwitch())
            if let direction = result.direction { switchDirection(direction) }
            return result.consume
        }
        status = installed && access.isRunning ? .ready : .unavailable
    }

    func stop() {
        access.remove()
        recognizer = AppBarSwipeRecognizer()
        status = .stopped
    }
}

// 回调在主线程运行且不等待 HTTP；这里仅持有和释放系统 tap。
@MainActor
private final class SystemAppBarSwipeAccess: AppBarSwipeAccess {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((NSEvent) -> Bool)?
    var isRunning: Bool {
        guard let tap, CFMachPortIsValid(tap) else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func install(handler: @escaping (NSEvent) -> Bool) -> Bool {
        self.handler = handler
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let access = Unmanaged<SystemAppBarSwipeAccess>.fromOpaque(context).takeUnretainedValue()
                    // 定时检测会重建失效的 tap，同时重置手势状态，避免沿用半途失效的滑动。
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        return Unmanaged.passUnretained(event)
                    }
                    guard let input = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
                    return access.handler?(input) == true ? nil : Unmanaged.passUnretained(event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return isRunning
    }

    func remove() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        handler = nil
    }
}
