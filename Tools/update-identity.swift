import Foundation
import Security

// Print public signed-app identity only. Never accepts or reads a private key.
guard CommandLine.arguments.count == 2 else { fatalError("Usage: update-identity APP") }
let app = URL(fileURLWithPath: CommandLine.arguments[1])
var code: SecStaticCode?, rule: SecRequirement?, ruleText: CFString?, info: CFDictionary?
guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
      SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), nil) == errSecSuccess,
      SecCodeCopyDesignatedRequirement(code, [], &rule) == errSecSuccess, let rule,
      SecRequirementCopyString(rule, [], &ruleText) == errSecSuccess, let ruleText,
      SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
      let bytes = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data, bytes.count == 20,
      let bundle = Bundle(url: app), let identifier = bundle.bundleIdentifier,
      let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      let lid = bundle.object(forInfoDictionaryKey: "PerchLidProtocolVersion") as? Int else { fatalError("Cannot verify signed Perch app") }
let object: [String: Any] = ["schema": 1, "bundle": identifier, "build": build,
    "codeHash": bytes.map { String(format: "%02x", $0) }.joined(), "requirement": ruleText as String, "lidProtocol": lid]
let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
