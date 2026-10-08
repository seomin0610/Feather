//
//  UpdatesWidget.swift
//  FeatherWidget
//

import SwiftUI
import WidgetKit

@main
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

	private let _tint = Color(red: 0x84 / 255, green: 0x8e / 255, blue: 0xf9 / 255)

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			if let snapshot, !snapshot.apps.isEmpty {
				Image(systemName: "arrow.down.circle.fill")
					.font(.title2)
					.foregroundStyle(_tint)
				Spacer(minLength: 0)
				HStack(alignment: .firstTextBaseline, spacing: 3) {
					Text("\(snapshot.apps.count)")
						.font(.system(size: 40, weight: .bold, design: .rounded))
					Text(LocalizedStringKey(snapshot.apps.count == 1 ? "app" : "apps"))
						.font(.subheadline.weight(.semibold))
				}
				.foregroundStyle(_tint)
				Text("Updates Available")
					.font(.subheadline.weight(.semibold))
					.lineLimit(1)
					.minimumScaleFactor(0.8)
				_appsLine(snapshot.apps)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			} else if let snapshot {
				Image(systemName: "checkmark.circle.fill")
					.font(.title2)
					.foregroundStyle(.green)
				Spacer(minLength: 0)
				Text("Up to Date")
					.font(.headline)
				Group {
					if date.timeIntervalSince(snapshot.checkedAt) < 60 {
						Text("\(Text(snapshot.checkedAt, style: .relative)) ago")
					} else {
						Text(_relativeFormatter.localizedString(for: snapshot.checkedAt, relativeTo: date))
					}
				}
				.font(.caption)
				.foregroundStyle(.secondary)
			} else {
				Image(systemName: "arrow.down.circle.fill")
					.font(.title2)
					.foregroundStyle(.secondary)
				Spacer(minLength: 0)
				Text("Open Feather to check for updates")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.widgetBackground()
	}

	private var _relativeFormatter: RelativeDateTimeFormatter {
		let formatter = RelativeDateTimeFormatter()
		formatter.dateTimeStyle = .named
		return formatter
	}

	private func _appsLine(_ apps: [UpdateWidgetSnapshot.App]) -> Text {
		apps.enumerated().reduce(Text(verbatim: "")) { line, item in
			let separator = item.offset == 0 ? "" : ", "
			let icon = item.element.icon
				.flatMap { UIImage(data: $0, scale: 3) }
				.map { Text("\(Text(Image(uiImage: $0).renderingMode(.original)).baselineOffset(-3)) ") } ?? Text(verbatim: "")
			return Text("\(line)\(separator)\(icon)\(item.element.name)")
		}
	}
}

private extension View {
	@ViewBuilder
	func widgetBackground() -> some View {
		if #available(iOS 17.0, *) {
			containerBackground(.background, for: .widget)
		} else {
			padding().background(Color(uiColor: .systemBackground))
		}
	}
}
