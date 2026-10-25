//
//  TaskProgressLiveActivity.swift
//  FeatherWidget
//

import ActivityKit
import SwiftUI
import WidgetKit

struct TaskProgressLiveActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: TaskProgressAttributes.self) { context in
			_Summary(guide: context.attributes, state: context.state, tint: context.attributes.tintColor, onDark: false)
				.padding(.horizontal, 18)
				.padding(.vertical, 16)
				.activitySystemActionForegroundColor(context.attributes.tintColor)
		} dynamicIsland: { context in
			let tint = context.attributes.tintColor

			return DynamicIsland {
				DynamicIslandExpandedRegion(.bottom) {
					_Summary(guide: context.attributes, state: context.state, tint: tint, onDark: true)
						.padding(.horizontal, 6)
						.padding(.bottom, 4)
				}
			} compactLeading: {
				Image("CompactGlyph")
					.foregroundStyle(tint)
			} compactTrailing: {
				_Ring(progress: context.attributes.overall(context.state), tint: tint)
			} minimal: {
				_Ring(progress: context.attributes.overall(context.state), tint: tint)
			}
			.keylineTint(tint)
		}
	}
}

// MARK: - Pieces
private struct _Summary: View {
	let guide: TaskProgressAttributes
	let state: TaskProgressAttributes.ContentState
	let tint: Color
	let onDark: Bool

	private var _muted: Color { onDark ? .white.opacity(0.55) : .secondary }

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline) {
				VStack(alignment: .leading, spacing: 1) {
					Text(verbatim: guide.title)
						.font(.system(size: 17, weight: .bold))
						.foregroundStyle(onDark ? Color.white : Color.primary)
						.lineLimit(1)

					if guide.stages.count < 2 {
						Text(verbatim: state.step)
							.font(.system(size: 13, weight: .medium))
							.foregroundStyle(_muted)
							.lineLimit(1)
					}
				}

				Spacer(minLength: 12)

				Text(verbatim: "\(Int(state.progress * 100))%")
					.font(.system(size: 22, weight: .semibold, design: .rounded))
					.monospacedDigit()
					.foregroundStyle(tint)
					.contentTransition(.numericText())
			}

			if guide.stages.count < 2 {
				_Track(progress: state.progress, goal: guide.goal, tint: tint, muted: _muted, onDark: onDark)
			} else {
				_StagedTrack(stages: guide.stages, state: state, tint: tint, muted: _muted, onDark: onDark)
			}
		}
	}
}

private struct _Track: View {
	let progress: Double
	let goal: String?
	let tint: Color
	let muted: Color
	let onDark: Bool

	private var _isDone: Bool { progress >= 1 }

	var body: some View {
		VStack(alignment: .trailing, spacing: 5) {
			_Fill(progress: progress, tint: tint, onDark: onDark)
				.overlay(alignment: .trailing) {
					_Stop(isReached: _isDone, tint: tint, muted: muted, onDark: onDark)
				}
				.frame(height: _Stop.size)

			if let goal {
				Text(verbatim: goal)
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(_isDone ? tint : muted)
					.lineLimit(1)
			}
		}
	}
}

private struct _StagedTrack: View {
	let stages: [String]
	let state: TaskProgressAttributes.ContentState
	let tint: Color
	let muted: Color
	let onDark: Bool

	private var _isDone: Bool { state.stage >= stages.count - 1 && state.progress >= 1 }

	var body: some View {
		HStack(alignment: .top, spacing: 8) {
			ForEach(Array(stages.enumerated()), id: \.offset) { index, name in
				VStack(spacing: 5) {
					_Fill(progress: _fill(for: index), tint: tint, onDark: onDark)
						.overlay(alignment: .trailing) {
							if index == stages.count - 1 {
								_Stop(isReached: _isDone, tint: tint, muted: muted, onDark: onDark)
							}
						}
						.frame(height: _Stop.size)

					Text(verbatim: name)
						.font(.system(size: 11, weight: index == state.stage ? .semibold : .regular))
						.foregroundStyle(index == state.stage && !_isDone ? tint : muted)
						.lineLimit(1)
						.minimumScaleFactor(0.8)
				}
			}
		}
	}

	private func _fill(for index: Int) -> Double {
		if index < state.stage { return 1 }
		if index > state.stage { return 0 }
		return state.progress
	}
}

private struct _Fill: View {
	let progress: Double
	let tint: Color
	let onDark: Bool

	private let _line: CGFloat = 6

	var body: some View {
		GeometryReader { proxy in
			ZStack(alignment: .leading) {
				Capsule()
					.fill(onDark ? Color.white.opacity(0.16) : Color.primary.opacity(0.1))
				if progress > 0 {
					Capsule()
						.fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing))
						.frame(width: max(_line, proxy.size.width * min(progress, 1)))
				}
			}
		}
		.frame(height: _line)
	}
}

private struct _Stop: View {
	let isReached: Bool
	let tint: Color
	let muted: Color
	let onDark: Bool

	static let size: CGFloat = 18
	// the system crossfades between states, a change of size smears
	private var _size: CGFloat { Self.size }

	private var _base: Color {
		onDark ? Color(white: 0.16) : Color(uiColor: .systemGray5)
	}

	var body: some View {
		Circle()
			.strokeBorder(isReached ? Color.green : muted, lineWidth: 2.5)
			.background(Circle().fill(isReached ? Color.green : _base))
			.overlay(
				Image(systemName: "checkmark")
					.font(.system(size: _size * 0.45, weight: .heavy))
					.foregroundStyle(isReached ? Color.white : muted)
			)
			.frame(width: _size, height: _size)
	}
}

private struct _Ring: View {
	let progress: Double
	let tint: Color

	var body: some View {
		ZStack {
			Circle()
				.stroke(tint.opacity(0.25), lineWidth: 2.5)
			Circle()
				.trim(from: 0, to: min(max(progress, 0.02), 1))
				.stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
				.rotationEffect(.degrees(-90))
		}
		.frame(width: 16, height: 16)
	}
}

extension TaskProgressAttributes {
	var tintColor: Color {
		Color(tintHex: tint)
	}

	func overall(_ state: ContentState) -> Double {
		guard stages.count > 1 else { return state.progress }
		return (Double(state.stage) + state.progress) / Double(stages.count)
	}
}
