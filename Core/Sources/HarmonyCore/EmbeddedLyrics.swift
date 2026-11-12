import Foundation

public enum EmbeddedLyrics {
    public static func parse(_ text: String, artist: String? = nil, title: String? = nil) -> StructuredLyrics {
        let rows = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var lines: [LyricLine] = []
        var plain: [LyricLine] = []
        var offset: Double = 0
        for row in rows {
            var remainder = row[...]
            var starts: [Double] = []
            var header = false
            while remainder.first == "[", let end = remainder.firstIndex(of: "]") {
                let tag = String(remainder[remainder.index(after: remainder.startIndex)..<end])
                if let start = timestamp(tag) {
                    starts.append(start)
                } else if tag.lowercased().hasPrefix("offset:"), let value = Double(tag.dropFirst(7)), value.isFinite {
                    // LRC positive offsets show lines sooner, matching StructuredLyrics' advancing offset.
                    offset = value; header = true
                } else if ["ti:", "ar:", "al:", "by:", "re:", "ve:", "length:"].contains(where: {
                    tag.lowercased().hasPrefix($0)
                }) {
                    header = true
                } else {
                    break
                }
                remainder = remainder[remainder.index(after: end)...]
            }
            if !starts.isEmpty {
                for start in starts { lines.append(LyricLine(start: start, value: String(remainder))) }
            } else if !header {
                plain.append(LyricLine(value: row))
            }
        }
        if !lines.isEmpty {
            // Stable order for repeated timestamps and multiple timestamps on one line.
            let sorted = lines.enumerated().sorted {
                if $0.element.start == $1.element.start { return $0.offset < $1.offset }
                return ($0.element.start ?? 0) < ($1.element.start ?? 0)
            }.map(\.element)
            return StructuredLyrics(
                displayArtist: artist, displayTitle: title, synced: true, offset: offset, line: sorted)
        }
        return StructuredLyrics(displayArtist: artist, displayTitle: title, line: plain)
    }
    private static func timestamp(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        // Legacy [mm:ss:xx] uses a colon before hundredths; [h:mm:ss.xx] always has a decimal point.
        if parts.count == 3, (1...3).contains(parts[2].count),
            parts[2].allSatisfy({ $0.isASCII && $0.isNumber }), let fraction = Int(parts[2]), fraction >= 0,
            let minutes = Int(parts[0]), minutes >= 0, let seconds = Int(parts[1]), (0..<60).contains(seconds)
        {
            let scale = parts[2].count == 3 ? 1.0 : parts[2].count == 2 ? 10.0 : 100.0
            return (Double(minutes) * 60 + Double(seconds)) * 1000 + Double(fraction) * scale
        }
        guard parts.count == 2 || parts.count == 3, let minutes = Int(parts[parts.count - 2]), minutes >= 0,
            let seconds = Double(parts.last!), seconds.isFinite, seconds >= 0, seconds < 60
        else { return nil }
        var value = Double(minutes) * 60 + seconds
        if parts.count == 3 {
            guard let hours = Int(parts[0]), hours >= 0, minutes < 60 else { return nil }
            value += Double(hours) * 3600
        }
        value *= 1000
        return value.isFinite ? value : nil
    }
}
