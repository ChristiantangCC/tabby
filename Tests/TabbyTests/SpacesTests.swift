import Testing
@testable import Tabby

@Suite("Which Spaces Tabby looks at beyond the current one")
struct SpacesTests {
    private func display(current: Int, _ spaces: [(id: Int, fullScreen: Bool)]) -> [String: Any] {
        [
            "Current Space": ["ManagedSpaceID": current],
            "Spaces": spaces.map { ["ManagedSpaceID": $0.id, "type": $0.fullScreen ? 4 : 0] },
        ]
    }

    @Test func noFullScreenMeansNothingExtra() {
        let displays = [display(current: 1, [(1, false)]), display(current: 8, [(8, false)])]
        #expect(FullScreenSpaces.extraSpaceIDs(displays: displays).isEmpty)
    }

    @Test("On the desktop: full-screen Spaces are added, the desktop is already covered")
    func onDesktopAddsFullScreenOnly() {
        let displays = [display(current: 9, [(9, false), (58, true)])]
        #expect(FullScreenSpaces.extraSpaceIDs(displays: displays) == [58])
    }

    @Test("Inside full screen: the desktop behind it is added too, so its windows don't vanish")
    func insideFullScreenAddsDesktopBehind() {
        let displays = [display(current: 58, [(9, false), (58, true)])]
        #expect(FullScreenSpaces.extraSpaceIDs(displays: displays) == [9, 58])
    }

    @Test("Other screens are unaffected by one screen being in full screen")
    func otherScreensUnaffected() {
        let displays = [
            display(current: 1, [(1, false)]),
            display(current: 58, [(9, false), (58, true)]),
        ]
        #expect(FullScreenSpaces.extraSpaceIDs(displays: displays) == [9, 58])
    }
}
