import XCTest
@testable import PowerBarPro

final class StreamingJSONParserTests: XCTestCase {

    var parser: StreamingJSONParser!

    override func setUp() {
        super.setUp()
        parser = StreamingJSONParser()
    }

    // MARK: - Basic Parsing

    func testFeed_singleCompactObject() {
        let results = parser.feed(#"{"key":"value"}"#)
        XCTAssertEqual(results.count, 1)

        let dict = try! JSONSerialization.jsonObject(with: results[0]) as! [String: String]
        XCTAssertEqual(dict["key"], "value")
    }

    func testFeed_prettyPrintedObject() {
        let json = """
        {
          "name": "test",
          "value": 42
        }
        """
        let results = parser.feed(json)
        XCTAssertEqual(results.count, 1)
    }

    func testFeed_twoObjectsInOneChunk() {
        let json = #"{"a":1}{"b":2}"#
        let results = parser.feed(json)
        XCTAssertEqual(results.count, 2)
    }

    func testFeed_twoObjectsSeparatedByWhitespace() {
        let json = """
        {"a": 1}

        {"b": 2}
        """
        let results = parser.feed(json)
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Split Across Chunks

    func testFeed_objectSplitAcrossTwoChunks() {
        let r1 = parser.feed(#"{"key":"val"#)
        XCTAssertEqual(r1.count, 0) // Not complete yet

        let r2 = parser.feed(#"ue"}"#)
        XCTAssertEqual(r2.count, 1) // Now complete
    }

    func testFeed_objectSplitAcrossThreeChunks() {
        XCTAssertEqual(parser.feed("{").count, 0)
        XCTAssertEqual(parser.feed(#""x":"#).count, 0)
        XCTAssertEqual(parser.feed(#"1}"#).count, 1)
    }

    func testFeed_multipleObjectsSplitAcrossChunks() {
        let r1 = parser.feed("{\"a\":1}{\"b\"")
        XCTAssertEqual(r1.count, 1) // First complete

        let r2 = parser.feed(":2}")
        XCTAssertEqual(r2.count, 1) // Second complete
    }

    // MARK: - Nested Objects

    func testFeed_nestedObjects() {
        let json = #"{"outer":{"inner":{"deep":true}}}"#
        let results = parser.feed(json)
        XCTAssertEqual(results.count, 1)
    }

    func testFeed_nestedArrays() {
        let json = #"{"data":[1,[2,3],{"a":4}]}"#
        let results = parser.feed(json)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Strings with Special Characters

    func testFeed_stringContainingBraces() {
        let json = #"{"msg":"hello {world}"}"#
        let results = parser.feed(json)
        XCTAssertEqual(results.count, 1)
    }

    func testFeed_stringContainingEscapedQuotes() {
        let json = #"{"msg":"he said \"hi\""}"#
        let results = parser.feed(json)
        XCTAssertEqual(results.count, 1)
    }

    func testFeed_stringContainingBackslashes() {
        let json = #"{"path":"C:\\Users\\test"}"#
        let results = parser.feed(json)
        XCTAssertEqual(results.count, 1)
    }

    func testFeed_stringContainingEscapedBraces() {
        // JSON string with literal braces inside
        let json = #"{"template":"{{name}}"}"#
        let results = parser.feed(json)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Empty & Edge Cases

    func testFeed_emptyString() {
        let results = parser.feed("")
        XCTAssertTrue(results.isEmpty)
    }

    func testFeed_whitespaceOnly() {
        let results = parser.feed("   \n\n\t  ")
        XCTAssertTrue(results.isEmpty)
    }

    func testFeed_leadingGarbage() {
        // Text before first { is ignored
        let results = parser.feed(#"some text {"a":1}"#)
        XCTAssertEqual(results.count, 1)
    }

    func testFeed_extraClosingBrace() {
        // Malformed: extra } should not crash (depth floors at 0)
        let results = parser.feed(#"}{"a":1}"#)
        XCTAssertEqual(results.count, 1)
    }

    func testFeed_emptyObject() {
        let results = parser.feed("{}")
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Reset

    func testReset_discardsPartialBuffer() {
        _ = parser.feed(#"{"partial"#) // Incomplete
        parser.reset()

        // After reset, a new object should work fine
        let results = parser.feed(#"{"new":1}"#)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Realistic macpow Output

    func testFeed_realisticMacpowJSON() {
        let macpowOutput = """
        {
          "soc": {
            "cpu_w": 3.2,
            "gpu_w": 0.5,
            "total_w": 8.0
          },
          "sys_power_w": 12.1,
          "top_processes": [
            {"pid": 123, "name": "Safari"}
          ]
        }
        """
        let results = parser.feed(macpowOutput)
        XCTAssertEqual(results.count, 1)

        // Verify it's valid JSON
        let obj = try! JSONSerialization.jsonObject(with: results[0]) as! [String: Any]
        XCTAssertEqual(obj["sys_power_w"] as? Double, 12.1)
    }

    func testFeed_twoMacpowSamples() {
        let sample1 = """
        {
          "sys_power_w": 10.0
        }
        """
        let sample2 = """
        {
          "sys_power_w": 12.0
        }
        """
        let r1 = parser.feed(sample1)
        XCTAssertEqual(r1.count, 1)

        let r2 = parser.feed(sample2)
        XCTAssertEqual(r2.count, 1)
    }
}
