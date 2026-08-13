import Testing

import Mockable

// An associated type the mock has to fulfill with a concrete type, and a generic type
// alias whose clauses the mock has to keep. Compiling these mocks is most of the test.

@Mockable
protocol ConstrainedStore {
    associatedtype Item: Equatable = String
    func decode() -> Item
}

@Mockable
protocol GenericAliasHost {
    typealias Pair<Value> = (Value, Value)
    func makePair() -> Pair<Int>
}

@Suite("Associated Type Constraint Integration Tests")
struct AssociatedTypeConstraintTests {
    @Test("A constrained associated type is fulfilled with its default")
    func constrainedAssociatedTypeUsesDefault() {
        let mock = ConstrainedStoreMock()
        mock.decodeHandler = { "decoded" }

        #expect(mock.decode() == "decoded")
        // The default satisfies the constraint, so the mock's Item really is String.
        #expect(ConstrainedStoreMock.Item.self == String.self)
    }

    @Test("A generic type alias is usable through the mock")
    func genericTypeAlias() {
        let mock = GenericAliasHostMock()
        mock.makePairHandler = { (1, 2) }

        let pair: GenericAliasHostMock.Pair<Int> = mock.makePair()
        #expect(pair == (1, 2))
    }
}
