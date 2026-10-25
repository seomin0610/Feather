//
//  SettingsGuideLiveActivity.swift
//  FeatherWidget
//

import ActivityKit
import SwiftUI
import WidgetKit

struct SettingsGuideLiveActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: SettingsGuideAttributes.self) { context in
			_Instruction(guide: context.attributes, onDark: false)
				.padding(.horizontal, 18)
				.padding(.vertical, 16)
				.activitySystemActionForegroundColor(context.attributes.tintColor)
		} dynamicIsland: { context in
			let guide = context.attributes

			return DynamicIsland {
				DynamicIslandExpandedRegion(.bottom) {
					_Instruction(guide: guide, onDark: true)
						.padding(.horizontal, 6)
						.padding(.bottom, 4)
				}
			} compactLeading: {
				// Live Activities swap large images for a placeholder block
				Image("CompactGlyph")
					.foregroundStyle(guide.tintColor)
			} compactTrailing: {
				Image(systemName: guide.symbol)
					.font(.system(size: 14, weight: .semibold))
					.foregroundStyle(guide.tintColor)
			} minimal: {
				Image(systemName: guide.symbol)
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(guide.tintColor)
			}
			.keylineTint(guide.tintColor)
		}
	}
}

// MARK: - Pieces
private struct _Instruction: View {
	let guide: SettingsGuideAttributes
	let onDark: Bool

	private var _destination: String { guide.stops.last ?? "" }
	private var _way: [String] { Array(guide.stops.dropLast()) }

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(verbatim: guide.title)
				.font(.system(size: 13, weight: .semibold))
				.foregroundStyle(guide.tintColor)
				.lineLimit(1)

			Text(verbatim: _destination)
				.font(.system(size: 22, weight: .bold))
				.foregroundStyle(onDark ? Color.white : Color.primary)
				.lineLimit(1)
				.minimumScaleFactor(0.7)

			if !_way.isEmpty {
				_Way(stops: _way, onDark: onDark)
					.padding(.top, 2)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

private struct _Way: View {
	let stops: [String]
	let onDark: Bool

	private var _color: Color { onDark ? .white.opacity(0.55) : .secondary }

	var body: some View {
		stops.enumerated().reduce(Text(verbatim: "")) { line, item in
			guard item.offset > 0 else { return line + Text(verbatim: item.element) }
			let chevron = Text(Image(systemName: "chevron.right")).font(.system(size: 9, weight: .bold))
			return line + Text(verbatim: "  ") + chevron + Text(verbatim: "  \(item.element)")
		}
		.font(.system(size: 13, weight: .medium))
		.foregroundStyle(_color)
		.lineLimit(1)
		.minimumScaleFactor(0.75)
	}
}

extension SettingsGuideAttributes {
	var tintColor: Color {
		Color(tintHex: tint)
	}
}

extension Color {
	init(tintHex hex: String?) {
		let value = hex
			.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
			.flatMap { UInt64($0.prefix(6), radix: 16) } ?? 0x848EF9
		self.init(
			red: Double((value >> 16) & 0xff) / 255,
			green: Double((value >> 8) & 0xff) / 255,
			blue: Double(value & 0xff) / 255
		)
	}
}
