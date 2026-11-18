import Flutter
import Testing
import UIKit

@testable import fictura_flutter

/// The Swift side of the bridge. Run from Xcode (Runner scheme, Test) or
/// `xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17'`.
struct RunnerTests {
    @Test func dartNullsBecomeNSNullForTheSdk() throws {
        let out = Bridge.fromDart(["a": "x", "b": nil, "c": [1, nil] as [Any?], "d": ["e": nil] as [String: Any?]])
        #expect(out["a"] as? String == "x")
        #expect(out["b"] is NSNull)
        let list = try #require(out["c"] as? [Any])
        #expect(list[0] as? Int == 1)
        #expect(list[1] is NSNull)
        let nested = try #require(out["d"] as? [String: Any])
        #expect(nested["e"] is NSNull)
    }

    @Test func sdkNullsBecomeDartNulls() {
        let out = Bridge.toDart(["campaign": "tiktok", "deep_link": NSNull()])
        #expect(out["campaign"] as? String == "tiktok")
        #expect(out["deep_link"]! == nil)
    }
}
