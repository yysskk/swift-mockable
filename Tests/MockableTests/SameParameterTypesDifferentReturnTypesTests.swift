import Foundation
import Testing

import Mockable

@Mockable
protocol HttpService: Sendable {
    func get(url: URL) async -> String
    func get(url: URL) async throws -> Data
    func get(url: URL, httpHeader: [String: String]) async -> String
    func getNoCache(url: URL) async -> String
    func getNoCache(url: URL, httpHeader: [String: String]) async -> String
}

// MARK: - Same Parameter Types Different Return Types Tests

@Suite("Same Parameter Types Different Return Types Tests")
struct SameParameterTypesDifferentReturnTypesTests {
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Overloaded methods with same parameter types but different return types have separate handlers")
    func overloadedMethodsSameParamsDifferentReturnTypes() async throws {
        let mock = HttpServiceMock()

        // Set handlers for the two get(url:) overloads that differ only by return type and throws
        mock.getURLStringAsyncHandler = { @Sendable _ in "string result" }
        mock.getURLDataAsyncThrowingHandler = { @Sendable _ in Data("data result".utf8) }

        // Need to use type annotation to disambiguate overloaded methods
        let stringResult: String = await mock.get(url: URL(string: "https://example.com")!)
        let dataResult: Data = try await mock.get(url: URL(string: "https://example.com")!)

        #expect(stringResult == "string result")
        #expect(dataResult == Data("data result".utf8))
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Overloaded methods with same parameter types have separate call counts")
    func overloadedMethodsSameParamsSeparateCallCounts() async throws {
        let mock = HttpServiceMock()

        mock.getURLStringAsyncHandler = { @Sendable _ in "result" }
        mock.getURLDataAsyncThrowingHandler = { @Sendable _ in Data() }

        let _: String = await mock.get(url: URL(string: "https://example.com/1")!)
        let _: String = await mock.get(url: URL(string: "https://example.com/2")!)
        let _: Data = try await mock.get(url: URL(string: "https://example.com/3")!)

        #expect(mock.getURLStringAsyncCallCount == 2)
        #expect(mock.getURLDataAsyncThrowingCallCount == 1)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Overloaded methods with same parameter types have separate call args")
    func overloadedMethodsSameParamsSeparateCallArgs() async throws {
        let mock = HttpServiceMock()

        mock.getURLStringAsyncHandler = { @Sendable _ in "result" }
        mock.getURLDataAsyncThrowingHandler = { @Sendable _ in Data() }

        let url1 = URL(string: "https://example.com/string")!
        let url2 = URL(string: "https://example.com/data")!

        let _: String = await mock.get(url: url1)
        let _: Data = try await mock.get(url: url2)

        #expect(mock.getURLStringAsyncCallArgs.count == 1)
        #expect(mock.getURLStringAsyncCallArgs[0] == url1)

        #expect(mock.getURLDataAsyncThrowingCallArgs.count == 1)
        #expect(mock.getURLDataAsyncThrowingCallArgs[0] == url2)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Methods with different parameter counts use parameter-based suffixes")
    func methodsWithDifferentParamCountsUseParameterBasedSuffixes() async {
        let mock = HttpServiceMock()

        // get(url:) returning String and get(url:httpHeader:) have different parameter counts
        // get(url:httpHeader:) uses parameter-based suffix URLStringStringArray
        // because [String: String] is sanitized to StringStringArray (treated as array-like syntax)
        mock.getURLStringAsyncHandler = { @Sendable _ in "simple" }
        mock.getURLStringStringArrayHandler = { @Sendable _ in "with header" }

        let simpleResult: String = await mock.get(url: URL(string: "https://example.com")!)
        let headerResult = await mock.get(url: URL(string: "https://example.com")!, httpHeader: ["Auth": "token"])

        #expect(simpleResult == "simple")
        #expect(headerResult == "with header")
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Non-overloaded methods keep simple naming")
    func nonOverloadedMethodsKeepSimpleNaming() async {
        let mock = HttpServiceMock()

        mock.getNoCacheURLHandler = { @Sendable _ in "no cache result" }

        let result = await mock.getNoCache(url: URL(string: "https://example.com")!)

        #expect(result == "no cache result")
        #expect(mock.getNoCacheURLCallCount == 1)
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    @Test("Reset clears all overloaded method states including extended suffixes")
    func resetClearsAllOverloadedMethodStates() async throws {
        let mock = HttpServiceMock()

        mock.getURLStringAsyncHandler = { @Sendable _ in "result" }
        mock.getURLDataAsyncThrowingHandler = { @Sendable _ in Data() }
        mock.getURLStringStringArrayHandler = { @Sendable _ in "with header" }

        let _: String = await mock.get(url: URL(string: "https://example.com")!)
        let _: Data = try await mock.get(url: URL(string: "https://example.com")!)
        _ = await mock.get(url: URL(string: "https://example.com")!, httpHeader: [:])

        #expect(mock.getURLStringAsyncCallCount == 1)
        #expect(mock.getURLDataAsyncThrowingCallCount == 1)
        #expect(mock.getURLStringStringArrayCallCount == 1)

        mock.resetMock()

        #expect(mock.getURLStringAsyncCallCount == 0)
        #expect(mock.getURLDataAsyncThrowingCallCount == 0)
        #expect(mock.getURLStringStringArrayCallCount == 0)
        #expect(mock.getURLStringAsyncCallArgs.isEmpty)
        #expect(mock.getURLDataAsyncThrowingCallArgs.isEmpty)
        #expect(mock.getURLStringStringArrayCallArgs.isEmpty)
    }
}
