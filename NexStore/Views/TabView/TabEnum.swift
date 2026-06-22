//
//  TabEnum.swift
//  feather
//
//  Created by samara on 22.03.2025.
//

import SwiftUI
import NimbleViews

enum TabEnum: String, CaseIterable, Hashable {
    case files
	case library
	case settings
	case certificates
	case appstore
	case appleid
	var title: String {
		switch self {
        case .files:        return .localized("Files")
		case .library: 		return .localized("My Apps")
		case .settings: 	return .localized("Settings")
		case .certificates:	return .localized("Certificates")
		case .appstore: 	return .localized("App Store")
		case .appleid: 	    return .localized("Apple ID")
		}
	}
	
	var icon: String {
		switch self {
        case .files:        return "folder.fill"
		case .library: 		return "square.grid.2x2"
		case .settings: 	return "gearshape"
		case .certificates: return "person.text.rectangle"
		case .appstore: 	return "cart.fill"
		case .appleid: 	    return "applelogo"
		}
	}
	
	@ViewBuilder
	static func view(for tab: TabEnum) -> some View {
		switch tab {
        case .files: FilesView()
		case .library: LibraryView()
		case .settings: SettingsView()
		case .certificates: NBNavigationView(.localized("Certificates")) { CertificatesView() }
		case .appstore: AppstoreView()
		case .appleid: AppleIDView()
		}
	}
	
	static var defaultTabs: [TabEnum] {
		return [
            .appstore,
            .library,
            .certificates,
            .appleid,
            .files,
			.settings,
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return []
	}
}
