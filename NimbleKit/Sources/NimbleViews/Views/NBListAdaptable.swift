//
//  NBListAdaptable.swift
//  NimbleKit
//
//  Created by samara on 7.05.2025.
//

import SwiftUI

public struct NBListAdaptable<Content>: View where Content: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	
	private var _content: Content
	
	public init(@ViewBuilder content: () -> Content) {
		self._content = content()
	}
	
	public var body: some View {
		Group {
			if horizontalSizeClass == .compact {
				List {
					_content
				}
				.listStyle(.plain)
			} else {
				NBGrid {
					_content
				}
			}
		}
		.padding(.bottom, 80) // Extra space for bottom bar
	}
}
