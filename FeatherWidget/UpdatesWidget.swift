//
//  UpdatesWidget.swift
//  FeatherWidget
//

import SwiftUI
import WidgetKit

@main
struct FeatherWidgets: WidgetBundle {
	var body: some Widget {
		UpdatesWidget()
		SettingsGuideLiveActivity()
	}
}

struct UpdatesWidget: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "Updates", provider: UpdatesProvider()) { entry in
			UpdatesWidgetView(snapshot: entry.snapshot, date: entry.date)
		}
		.configurationDisplayName("Updates")
		.description("Shows available app updates.")
		.supportedFamilies([.systemSmall])
	}
}

struct UpdatesEntry: TimelineEntry {
	var date = Date()
	let snapshot: UpdateWidgetSnapshot?
}

struct UpdatesProvider: TimelineProvider {
	func placeholder(in context: Context) -> UpdatesEntry {
		UpdatesEntry(snapshot: UpdateWidgetSnapshot(apps: [.init(name: "Feather"), .init(name: "YouTube")], checkedAt: Date()))
	}

	func getSnapshot(in context: Context, completion: @escaping (UpdatesEntry) -> Void) {
		completion(context.isPreview ? placeholder(in: context) : UpdatesEntry(snapshot: .load()))
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<UpdatesEntry>) -> Void) {
		let snapshot = UpdateWidgetSnapshot.load()
		let now = Date()
		var dates = [now]

		if let checkedAt = snapshot?.checkedAt {
			let steps = (1..<60).map { Double($0) * 60 } + (1...24).map { Double($0) * 3600 }
			dates += steps.map { checkedAt.addingTimeInterval($0) }.filter { $0 > now }
		}

		completion(Timeline(
			entries: dates.map { UpdatesEntry(date: $0, snapshot: snapshot) },
			policy: .after((dates.last ?? now).addingTimeInterval(3600))
		))
	}
}

struct UpdatesWidgetView: View {
	let snapshot: UpdateWidgetSnapshot?
	var date = Date()

	private var _palette: _Palette {
		_Palette(hex: snapshot?.tint)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			if let snapshot, !snapshot.apps.isEmpty {
				_IconFan(apps: Array(snapshot.apps.prefix(3)), palette: _palette)
				Spacer(minLength: 0)
				Text("\(snapshot.apps.count) updates")
					.font(.system(size: 20, weight: .bold, design: .rounded))
					.foregroundStyle(_palette.accent)
					.lineLimit(1)
					.minimumScaleFactor(0.8)
				Text(verbatim: snapshot.apps.map(\.name).joined(separator: ", "))
					.font(.system(.caption, design: .rounded))
					.foregroundStyle(.secondary)
					.lineLimit(2)
					.padding(.top, 1)
			} else if let snapshot {
				Image(systemName: "checkmark")
					.font(.system(size: 32, weight: .semibold, design: .rounded))
					.foregroundStyle(_palette.accent)
					.padding(.top, 4)
					.padding(.leading, -3)
				Spacer(minLength: 0)
				Text("Up to date")
					.font(.system(size: 20, weight: .bold, design: .rounded))
					.lineLimit(1)
					.minimumScaleFactor(0.8)
				Group {
					if date.timeIntervalSince(snapshot.checkedAt) < 60 {
						Text("\(Text(snapshot.checkedAt, style: .relative)) ago")
					} else {
						Text(_relativeFormatter.localizedString(for: snapshot.checkedAt, relativeTo: date))
					}
				}
				.font(.system(.caption, design: .rounded))
				.foregroundStyle(.secondary)
				.padding(.top, 1)
			} else {
				Image("Glyph")
					.resizable()
					.scaledToFit()
					.frame(width: 44, height: 44)
					.foregroundStyle(_palette.accent)
					// the glyph has a lot of transparent margin, pull it back to the text edge
					.padding(.leading, -6)
				Spacer(minLength: 0)
				Text("Open Feather to check for updates")
					.font(.system(.subheadline, design: .rounded, weight: .semibold))
					.foregroundStyle(.secondary)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.widgetBackground(Color(uiColor: .systemBackground))
	}

	private var _relativeFormatter: RelativeDateTimeFormatter {
		let formatter = RelativeDateTimeFormatter()
		formatter.dateTimeStyle = .named
		return formatter
	}
}

// every shade comes from the app's tint
private struct _Palette {
	let tint: UIColor

	init(hex: String?) {
		let value = hex
			.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
			.flatMap { UInt64($0.prefix(6), radix: 16) } ?? 0x848EF9
		tint = UIColor(
			red: CGFloat((value >> 16) & 0xff) / 255,
			green: CGFloat((value >> 8) & 0xff) / 255,
			blue: CGFloat(value & 0xff) / 255,
			alpha: 1
		)
	}

	var brand: Color { Color(uiColor: tint) }
	/// Text and symbols, deepened on light backgrounds and softened on dark ones.
	var accent: Color { _shade(light: { ($0 * 1.15, $1 * 0.85) }, dark: { ($0 * 0.75, $1 * 1.05) }) }
	var shadow: Color { _shade(light: { s, _ in (s * 0.5, 0.24) }, dark: { s, _ in (s * 0.5, 0.24) }) }

	/// Maps the tint's saturation and brightness to a new pair for each appearance.
	private func _shade(
		light: @escaping (CGFloat, CGFloat) -> (CGFloat, CGFloat),
		dark: @escaping (CGFloat, CGFloat) -> (CGFloat, CGFloat)
	) -> Color {
		let tint = tint
		return Color(uiColor: UIColor { traits in
			var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
			tint.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

			let shade = traits.userInterfaceStyle == .dark ? dark : light
			let (newSaturation, newBrightness) = shade(saturation, brightness)
			return UIColor(hue: hue, saturation: min(newSaturation, 1), brightness: min(newBrightness, 1), alpha: 1)
		})
	}
}

private let _tileSize: CGFloat = 44

/// App icons tilted around a pivot below them, like a fanned feather.
private struct _IconFan: View {
	let apps: [UpdateWidgetSnapshot.App]
	let palette: _Palette

	// distance from the tile centre down to the pivot the fan rotates around
	private let _pivot: CGFloat = 120

	private var _angles: [Double] {
		switch apps.count {
		case 1: [0]
		case 2: [-8, 8]
		default: [-14, 0, 14]
		}
	}

	/// How far the leftmost tile reaches past the frame, so the fan lines up with the text below.
	private var _overhang: CGFloat {
		let angle = (_angles.map(abs).max() ?? 0) * .pi / 180
		guard angle > 0 else { return 0 }
		return _pivot * sin(angle) + _tileSize / 2 * (cos(angle) + sin(angle) - 1)
	}

	var body: some View {
		ZStack {
			ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
				_AppTile(app: app, palette: palette)
					.rotationEffect(
						.degrees(_angles[index]),
						anchor: UnitPoint(x: 0.5, y: 0.5 + _pivot / _tileSize)
					)
			}
		}
		.frame(width: _tileSize, height: _tileSize)
		.padding(.leading, _overhang)
		.padding(.top, 2)
	}
}

private struct _AppTile: View {
	let app: UpdateWidgetSnapshot.App
	let palette: _Palette

	private var _shape: RoundedRectangle {
		RoundedRectangle(cornerRadius: _tileSize * 0.225, style: .continuous)
	}

	var body: some View {
		Group {
			if let icon = app.icon.flatMap({ UIImage(data: $0, scale: 3) }) {
				Image(uiImage: icon)
					.resizable()
			} else {
				palette.brand.overlay(
					Text(verbatim: String(app.name.prefix(1)))
						.font(.system(size: 20, weight: .bold, design: .rounded))
						.foregroundStyle(.white)
				)
			}
		}
		.frame(width: _tileSize, height: _tileSize)
		.clipShape(_shape)
		.overlay(_shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
		.shadow(color: palette.shadow.opacity(0.18), radius: 3, y: 1)
	}
}

private extension View {
	@ViewBuilder
	func widgetBackground(_ color: Color) -> some View {
		if #available(iOS 17.0, *) {
			containerBackground(color, for: .widget)
		} else {
			padding().background(color)
		}
	}
}
