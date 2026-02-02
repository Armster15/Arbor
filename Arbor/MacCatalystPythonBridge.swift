import Foundation

// Mac Catalyst needs an alternative implementation because Python.xcframework
// is not compatible with Catalyst. These Swift functions provide that implementation,
// and @_cdecl exports C symbols that match the declarations used by main.m and
// exposed to Swift via the bridging header.

#if targetEnvironment(macCatalyst)

@_cdecl("crash_dialog")
public func crash_dialog_c(_ details: NSString?) {
    if let details {
        NSLog("%@", details)
    }
}

@_cdecl("format_traceback")
public func format_traceback_c(
    _ type: UnsafeMutableRawPointer?,
    _ value: UnsafeMutableRawPointer?,
    _ traceback: UnsafeMutableRawPointer?
) -> NSString {
    _ = type
    _ = value
    _ = traceback
    return ""
}

@_cdecl("start_python_runtime")
public func start_python_runtime_c(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32 {
    _ = argc
    _ = argv
    return 0
}

@_cdecl("finalize_python_runtime")
public func finalize_python_runtime_c() {
}

@_cdecl("pythonRunSimpleString")
public func pythonRunSimpleString_c(_ code: NSString?) -> Int32 {
    _ = code
    return 0
}

@_cdecl("pythonExecAndGetString")
public func pythonExecAndGetString_c(_ code: NSString?, _ variableName: NSString?) -> NSString {
    _ = code
    _ = variableName
    return ""
}

@_cdecl("pythonExecAndGetStringAsync")
public func pythonExecAndGetStringAsync_c(
    _ code: NSString?,
    _ variableName: NSString?,
    _ completion: (@convention(block) (NSString?) -> Void)?
) {
    _ = code
    _ = variableName
    if let completion {
        debugPrint("pythonExecAndGetStringAsync_c: completion called")
        completion("")
    }
}

#endif
