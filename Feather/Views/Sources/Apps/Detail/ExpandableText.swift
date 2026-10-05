//
//  ExpandableText.swift
//  Feather
//
//  Created by samsam on 7/26/25.
//


import SwiftUI

struct ExpandableText: View {
	let text: String
	let lineLimit: Int

	@State private var expanded: Bool = false
	@State private var truncated: Bool = false

	var body: some View {
		let markdown = Self._markdown(text)

		VStack(alignment: .leading, spacing: 4) {
			Text(markdown)
				.lineLimit(expanded ? nil : lineLimit)
				.background(
					Text(markdown)
						.lineLimit(lineLimit)
						.background(GeometryReader { proxy in
							Color.clear
								.onAppear {
									let totalHeight = proxy.size.height
									let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
									truncated = totalHeight > lineHeight * CGFloat(lineLimit)
								}
						})
						.hidden()
				)
				.gesture(
					TapGesture().onEnded {
						withAnimation {
							expanded.toggle()
						}
					},
					including: truncated && !expanded ? .all : .subviews
				)

			if truncated {
				Button(action: {
					withAnimation {
						expanded.toggle()
					}
				}) {
					Text(expanded ? .localized("Less") : .localized("More"))
						.font(.caption)
						.foregroundColor(.accentColor)
				}
			}
		}
	}
}

extension ExpandableText {
	private static func _markdown(_ text: String) -> AttributedString {
		var result = AttributedString()

		for (index, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
			if index > 0 {
				result += AttributedString("\n")
			}

			let indent = String(line.prefix { $0 == " " || $0 == "\t" })
			var content = String(line.dropFirst(indent.count))
			var isHeader = false

			let level = content.prefix { $0 == "#" }.count
			if (1...6).contains(level), content.dropFirst(level).first == " " {
				content = String(content.dropFirst(level + 1))
				isHeader = true
			} else if let marker = content.first, "-*+".contains(marker), content.dropFirst().first == " " {
				content = "• " + content.dropFirst(2)
			}

			var part = (try? AttributedString(
				markdown: indent + content,
				options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
			)) ?? AttributedString(indent + content)

			if isHeader {
				part.inlinePresentationIntent = .stronglyEmphasized
			}
			result += part
		}

		return result
	}
}
