import GRDB

/// Lazy observation with GRDB's native cancellation. Consume from a screen-owned Task.
public struct StorageObservation<Element: Sendable>: AsyncSequence, Sendable {
    private let observation: AsyncValueObservation<Element>
    init(_ observation: AsyncValueObservation<Element>) { self.observation = observation }
    public struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate var iterator: AsyncValueObservation<Element>.AsyncIterator
        public mutating func next() async throws -> Element? { try await iterator.next() }
    }
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(iterator: observation.makeAsyncIterator()) }
}
