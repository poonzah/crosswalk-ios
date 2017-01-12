// Copyright (c) 2014 Intel Corporation. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation

class XWalkStubGenerator {
    let mirror: XWalkReflection

    init(cls: AnyClass) {
        mirror = XWalkReflection(cls: cls)
    }
    init(reflection: XWalkReflection) {
        mirror = reflection
    }

    func generate(_ channelName: String, namespace: String, object: AnyObject? = nil) -> String {
        var stub = "(function(exports) {\n"
        for name in mirror.allMembers {
            if mirror.hasMethod(name) {
                stub += "exports.\(name) = \(generateMethodStub(name))\n"
            } else {
                var value = "undefined"
                if object != nil, let result = XWalkInvocation.call(object, selector: mirror.getGetter(name), arguments: nil) {
                    // Fetch initial value
                    let val: AnyObject = ((result.isObject ? result.nonretainedObjectValue : ((result as? NSNumber) as Any?)) as AnyObject?) ?? NSNull()
                    value = toJSONString(val)
                }
                stub += "Extension.defineProperty(exports, '\(name)', \(value), \(!mirror.isReadonly(name)));\n"
            }
        }
        if let script = userDefinedJavaScript() {
            stub += script
        }
        stub += "\n})(Extension.create(\(channelName), '\(namespace)'"
        if mirror.constructor != nil {
            stub += ", " + generateMethodStub("+", selector: mirror.constructor) + ", true"
        } else if mirror.hasMethod("function") {
            stub += ", function(){return arguments.callee.function.apply(arguments.callee, arguments);}"
        }
        stub += "));\n"
        return stub
    }

    fileprivate func generateMethodStub(_ name: String, selector: Selector? = nil, this: String = "this") -> String {
        var params = (selector ?? mirror.getMethod(name)).description.components(separatedBy: ":")
        params.remove(at: 0)
        params.removeLast()

        // deal with parameters without external name
        for i in 0..<params.count {
            if params[i].isEmpty {
                params[i] = "__\(i)"
            }
        }

        let isPromise = params.last == "_Promise"
        if isPromise { params.removeLast() }

        let list = params.joined(separator: ", ")
        var body = "invokeNative('\(name)', [\(list)"
        if isPromise {
            body = "var _this = \(this);\n    return new Promise(function(resolve, reject) {\n        _this.\(body)"
            body += (list.isEmpty ? "" : ", ") + "{'resolve': resolve, 'reject': reject}]);\n    });"
        } else {
            body = "\(this).\(body)]);"
        }
        return "function(\(list)) {\n    \(body)\n}"
    }

    fileprivate func userDefinedJavaScript() -> String? {
        var className = NSStringFromClass(self.mirror.cls)

        if (className as NSString).pathExtension.characters.count > 0 {
            className = (className as NSString).pathExtension
        }
        let bundle = Bundle(for: self.mirror.cls)
        if let path = bundle.path(forResource: className, ofType: "js") {
            if let content = try? String(contentsOfFile: path, encoding: String.Encoding.utf8) {
                return content
            }
        }
        return nil
    }
}

private extension NSNumber {
    var isBool: Bool {
        get {
            return CFGetTypeID(self) == CFBooleanGetTypeID()
        }
    }
}

private func toJSONString(_ object: AnyObject, isPretty: Bool=false) -> String {
    switch object {
    case is NSNull:
        return "null"
    case is NSError:
        return "\(object)"
    case let number as NSNumber:
        if number.isBool {
            return (number as Bool).description
        } else {
            return (number as NSNumber).stringValue
        }
    case is NSString:
        return "'\(object as! String)'"
    default:
        if let data = (try? JSONSerialization.data(withJSONObject: object,
            options: isPretty ? JSONSerialization.WritingOptions.prettyPrinted : JSONSerialization.WritingOptions(rawValue: 0))) as Data? {
                if let string = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
                    return string as String
                }
        }
        print("ERROR: Failed to convert object \(object) to JSON string")
        return ""
    }
}
