import ApplicationServices
import Foundation

func copyAttribute<T>(from element: AXUIElement, attribute: String) -> T? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

    guard result == .success else { return nil }
    return value as? T
}
