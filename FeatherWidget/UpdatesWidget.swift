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
			UpdatesWidgetView(snapshot: entry.snapshot)
		}
		.configurationDisplayName("Updates")
		.description("Shows available app updates.")
		.supportedFamilies([.systemSmall])
	}
}

struct UpdatesEntry: TimelineEntry {
	let date = Date()
	let snapshot: UpdateWidgetSnapshot?
}

struct UpdatesProvider: TimelineProvider {
	func placeholder(in context: Context) -> UpdatesEntry {
		UpdatesEntry(snapshot: UpdateWidgetSnapshot(appNames: ["Feather", "YouTube"], checkedAt: Date()))
	}

	func getSnapshot(in context: Context, completion: @escaping (UpdatesEntry) -> Void) {
		completion(context.isPreview ? placeholder(in: context) : UpdatesEntry(snapshot: .load()))
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<UpdatesEntry>) -> Void) {
		completion(Timeline(entries: [UpdatesEntry(snapshot: .load())], policy: .never))
	}
}

struct UpdatesWidgetView: View {
	let snapshot: UpdateWidgetSnapshot?

	private let _tint = Color(red: 0x84 / 255, green: 0x8e / 255, blue: 0xf9 / 255)

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			if let snapshot, !snapshot.appNames.isEmpty {
				Image(systemName: "arrow.down.circle.fill")
					.font(.title2)
					.foregroundStyle(_tint)
				Spacer(minLength: 0)
				Text("\(snapshot.appNames.count)")
					.font(.system(size: 40, weight: .bold, design: .rounded))
					.foregroundStyle(_tint)
				Text(LocalizedStringKey(snapshot.appNames.count == 1 ? "Update" : "Updates"))
					.font(.subheadline.weight(.semibold))
				Text(snapshot.appNames.joined(separator: ", "))
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
				Text("\(Text(snapshot.checkedAt, style: .relative)) ago")
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
