//
//  NavigationViewWrapper.swift
//  Stars
//
//  Created by samara on 7.04.2025.
//

import SwiftUI

public struct NBNavigationView<Content>: View where Content: View {
	private var _title: String
	private var _content: Content
	
	public init(
		_ title: String,
		@ViewBuilder content: () -> Content
	) {
		self._title = title
		self._content = content()
	}
	
	public var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: 0) {
				Text(_title)
					.font(.largeTitle)
					fontWeight(.bold)
					.padding(.leading, 16)
					.padding(.top, 8)
				
				_content
			}
			.navigationBarTitleDisplayMode(.inline)
		}
	}
}
