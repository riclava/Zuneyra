import Foundation
import Testing
@testable import Zuneyra

struct LibraryPresentationTests {
    @Test func importHistoryFiltersIncludeLegacyFailuresAndStoppedPartialImports() {
        let complete = ImportRecord(id: UUID(), date: .now, source: "Complete", report: ImportReport(added: 2))
        let legacy = ImportRecord(id: UUID(), date: .now, source: "Legacy", report: ImportReport(failures: ["Unreadable audio"]))
        let partial = ImportRecord(id: UUID(), date: .now, source: "Stopped",
                                   report: ImportReport(added: 1, failures: ["Unreadable audio"], cancelled: true))
        #expect(ImportHistoryFilter.all.includes(complete))
        #expect(!ImportHistoryFilter.failures.includes(complete))
        #expect(!ImportHistoryFilter.stopped.includes(complete))
        #expect(legacy.failureCount == 1)
        #expect(ImportHistoryFilter.failures.includes(legacy))
        #expect(!ImportHistoryFilter.stopped.includes(legacy))
        #expect(ImportHistoryFilter.failures.includes(partial))
        #expect(ImportHistoryFilter.stopped.includes(partial))
        #expect(partial.report.added == 1)
    }

    @Test func lyricsHandleOffsetsRepeatedTimesAndPlainText() {
        let lyrics = Lyrics("[offset:-500]\n[00:01.00][00:03.25]Hello\n[00:02]World")
        #expect(lyrics.lines.map(\.time) == [0.5, 1.5, 2.75])
        #expect(lyrics.lines.map(\.text) == ["Hello", "World", "Hello"])
        #expect(lyrics.activeLine(at: 0.1) == nil)
        #expect(lyrics.activeLine(at: 1.6) == 1)
        #expect(Lyrics("普通歌词").lines.isEmpty)
    }

    @Test func albumSortRespectsDiscBeforeTrackNumber() {
        var secondDisc = track(1, number: 1)
        secondDisc.discNumber = 2
        let firstDisc = track(2, number: 10)
        #expect(LibraryPresentation.albumTracks([secondDisc, firstDisc]) == [firstDisc, secondDisc])
    }

    @Test func navigationRestoresPoppedPagesAndClearsForwardOnNewRoute() {
        var navigation = PageNavigation<Int>()
        navigation.setPath([1, 2])
        navigation.setPath([]) // Also handles the system/header back action.
        #expect(!navigation.canGoBack && navigation.canGoForward)
        navigation.forward()
        #expect(navigation.path == [1])
        navigation.forward()
        #expect(navigation.path == [1, 2] && !navigation.canGoForward)
        navigation.back()
        navigation.setPath([1]) // Repeated binding updates must preserve history.
        #expect(navigation.canGoForward)
        navigation.setPath([1, 3])
        #expect(!navigation.canGoForward)
        navigation.forward()
        #expect(navigation.path == [1, 3])
    }

    private func track(
        _ index: Int,
        title: String = "Song",
        artist: String = "Artist",
        album: String = "Album",
        albumArtist: String = "Album Artist",
        number: Int = 0,
        filename: String = "song.flac"
    ) -> Track {
        Track(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
            title: title, artist: artist, album: album, albumArtist: albumArtist,
            trackNumber: number, duration: 180, filename: filename,
            digest: "digest-\(index)", artwork: nil
        )
    }

    @Test func albumOrderUsesTrackNumbersAndPutsMissingNumbersLast() {
        let first = track(1, title: "Opening", number: 1)
        let second = track(2, title: "Track 2", number: 2)
        let secondAlternate = track(3, title: "Track 10", number: 2)
        let tenth = track(4, title: "Finale", number: 10)
        let missing = track(5, title: "Bonus 10", number: 0)
        let invalid = track(6, title: "Bonus 2", number: -1)
        let input = [tenth, missing, secondAlternate, invalid, second, first]

        #expect(LibraryPresentation.albumTracks(input) == [first, second, secondAlternate, tenth, invalid, missing])
    }

    @Test func titleAndArtistSortUseNaturalOrdering() {
        let songTwo = track(1, title: "Song 2", artist: "Artist 10")
        let songTen = track(2, title: "Song 10", artist: "Artist 2")
        let sameArtist = track(3, title: "Song 3", artist: "Artist 2")
        let input = [songTen, songTwo, sameArtist]

        #expect(LibrarySongSort.title.apply(to: input) == [songTwo, sameArtist, songTen])
        #expect(LibrarySongSort.artist.apply(to: input) == [sameArtist, songTen, songTwo])
    }

    @Test func equalTitlesUseFilenameThenIdentityForStableOrdering() {
        let first = track(1, number: 1, filename: "take 2.flac")
        let sameFilename = track(2, number: 1, filename: "take 2.flac")
        let laterFilename = track(3, number: 1, filename: "take 10.flac")
        let input = [laterFilename, sameFilename, first]
        let expected = [first, sameFilename, laterFilename]

        for sort in [LibrarySongSort.title, .artist] {
            #expect(sort.apply(to: input) == expected)
            #expect(sort.apply(to: Array(input.reversed())) == expected)
        }
        #expect(LibraryPresentation.albumTracks(input) == expected)
        #expect(LibraryPresentation.albumTracks(Array(input.reversed())) == expected)
    }

    @Test func recentSortPreservesRepositoryOrder() {
        let input = [track(3, title: "Third"), track(1, title: "First"), track(2, title: "Second")]
        #expect(LibrarySongSort.recent.apply(to: input) == input)
    }

    @Test func searchTrimsWhitespaceAndFindsEveryDisplayedMetadataFieldAndFilename() {
        let song = track(
            1, title: "晚风", artist: "Soloist", album: "夜航",
            albumArtist: "Ensemble", filename: "live_02.flac"
        )

        for query in ["风", "SOLOIST", "夜航", "ensemble", " \nLIVE_02.FLAC\t ", "", " \n\t "] {
            #expect(LibraryPresentation.matches(song, query: query))
        }
        #expect(!LibraryPresentation.matches(song, query: "missing"))
        #expect(!LibraryPresentation.matches(song, query: "live_03"))
    }
}
