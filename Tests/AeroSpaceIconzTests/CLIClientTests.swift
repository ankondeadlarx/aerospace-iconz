import Testing
@testable import AeroSpaceIconz

@Suite struct CLIClientTests {
    @Test func subscriptionThatFailsToLaunchIsNotTracked() async {
        let client = CLIClient(candidates: ["/nonexistent/aerospace"])
        for await _ in client.events() {}
        #expect(Subscriptions.liveCount == 0)
    }
}
