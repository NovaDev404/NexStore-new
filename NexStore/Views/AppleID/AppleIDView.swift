//
//  AppleIDView.swift
//  NexStore
//
//  Created for Apple ID signing functionality
//

import SwiftUI
import NimbleViews
import StosSign
import StosSign_API
import StosSign_Auth

@MainActor
class AppleIDManager: ObservableObject {
    @Published var account: Account?
    @Published var session: AppleAPISession?
    @Published var teams: [Team] = []
    @Published var appIDs: [AppID] = []
    @Published var certificates: [Certificate] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSignedIn = false
    
    private let api = AppleAPI.shared
    
    func signIn(appleID: String, password: String, anisetteData: AnisetteData) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let (account, session) = try await api.authenticate(
                appleID: appleID,
                password: password,
                anisetteData: anisetteData
            ) { verificationHandler in
                // This will be called when 2FA is required
                Task { @MainActor in
                    // For now, we'll need to implement a UI to handle 2FA
                    // This is a placeholder - we'll need to add proper 2FA UI
                }
            }
            
            self.account = account
            self.session = session
            self.isSignedIn = true
            
            // Fetch teams
            self.teams = try await api.fetchTeamsForAccount(account: account, session: session)
            
            // Fetch app IDs and certificates for the first team
            if let firstTeam = teams.first {
                await fetchAppIDs(for: firstTeam)
                await fetchCertificates(for: firstTeam)
            }
            
        } catch {
            self.errorMessage = error.localizedDescription
            self.isSignedIn = false
        }
        
        isLoading = false
    }
    
    func fetchAppIDs(for team: Team) async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let session = session else { return }
            self.appIDs = try await api.fetchAppIDsForTeam(team: team, session: session)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func fetchCertificates(for team: Team) async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let session = session else { return }
            self.certificates = try await api.fetchCertificatesForTeam(team: team, session: session)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func deleteAppID(_ appID: AppID, team: Team) async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let session = session else { return }
            let success = try await api.deleteAppID(appID, team: team, session: session)
            if success {
                appIDs.removeAll { $0.identifier == appID.identifier }
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func revokeCertificate(_ certificate: Certificate, team: Team) async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let session = session else { return }
            let success = try await api.revokeCertificate(certificate: certificate, team: team, session: session)
            if success {
                certificates.removeAll { $0.serialNumber == certificate.serialNumber }
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func signOut() {
        account = nil
        session = nil
        teams = []
        appIDs = []
        certificates = []
        isSignedIn = false
        errorMessage = nil
    }
}

struct AppleIDView: View {
    @StateObject private var manager = AppleIDManager()
    @State private var appleID = ""
    @State private var password = ""
    @State private var showingSignIn = true
    
    var body: some View {
        NBNavigationView(.localized("Apple ID")) {
            if showingSignIn || !manager.isSignedIn {
                signInView
            } else {
                accountView
            }
        }
        .padding(.bottom, 80)
    }
    
    private var signInView: some View {
        Form {
            Section {
                TextField("Apple ID", text: $appleID)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Sign in with your Apple Developer account")
            } footer: {
                Text("Your Apple ID is used to sign apps with your personal developer certificate.")
            }
            
            if let errorMessage = manager.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            Section {
                Button(action: {
                    Task {
                        // For now, we need anisette data
                        // This is a placeholder - we'll need to implement proper anisette handling
                        let anisetteData = AnisetteData(
                            machineID: "placeholder",
                            oneTimePassword: "placeholder",
                            localUserID: "placeholder",
                            routingInfo: 0,
                            deviceUniqueIdentifier: "placeholder",
                            deviceSerialNumber: "placeholder",
                            deviceDescription: "placeholder",
                            date: Date(),
                            locale: Locale.current,
                            timeZone: TimeZone.current
                        )
                        
                        await manager.signIn(appleID: appleID, password: password, anisetteData: anisetteData)
                        
                        if manager.isSignedIn {
                            showingSignIn = false
                        }
                    }
                }) {
                    HStack {
                        if manager.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Sign In")
                    }
                }
                .disabled(manager.isLoading || appleID.isEmpty || password.isEmpty)
            }
        }
        .navigationTitle("Apple ID")
    }
    
    private var accountView: some View {
        List {
            if let account = manager.account {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(account.name)
                                    .font(.headline)
                                Text(account.appleID)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Account")
                }
                
                Section {
                    ForEach(manager.teams, id: \.identifier) { team in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(team.name)
                                .font(.headline)
                            Text(teamTypeString(team.type))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Teams")
                }
                
                Section {
                    NavigationLink(destination: AppIDsView(manager: manager)) {
                        HStack {
                            Image(systemName: "app.badge")
                            Text("App IDs")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(manager.appIDs.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    NavigationLink(destination: CertificatesView(manager: manager)) {
                        HStack {
                            Image(systemName: "certificate")
                            Text("Certificates")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(manager.certificates.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Developer Resources")
                }
                
                Section {
                    Button(action: {
                        manager.signOut()
                        showingSignIn = true
                        appleID = ""
                        password = ""
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.square")
                                .foregroundColor(.red)
                            Text("Sign Out")
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Signing out will remove your account information from this device.")
                }
            }
        }
        .navigationTitle("Apple ID")
        .refreshable {
            if let firstTeam = manager.teams.first {
                await manager.fetchAppIDs(for: firstTeam)
                await manager.fetchCertificates(for: firstTeam)
            }
        }
    }
    
    private func teamTypeString(_ type: TeamType) -> String {
        switch type {
        case .individual:
            return "Individual"
        case .organization:
            return "Organization"
        case .free:
            return "Free"
        case .unknown:
            return "Unknown"
        }
    }
}

struct AppIDsView: View {
    @ObservedObject var manager: AppleIDManager
    @State private var selectedTeam: Team?
    
    var body: some View {
        List {
            if manager.appIDs.isEmpty {
                Section {
                    Text("No App IDs")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(manager.appIDs.indices, id: \.self) { index in
                    let appID = manager.appIDs[index]
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appID.name)
                                .font(.headline)
                            Text(appID.bundleIdentifier)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let expirationDate = appID.expirationDate {
                                Text("Expires: \(expirationDate, formatter: dateFormatter)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Button(role: .destructive) {
                            Task {
                                if let team = selectedTeam ?? manager.teams.first {
                                    await manager.deleteAppID(appID, team: team)
                                }
                            }
                        } label: {
                            Text("Delete App ID")
                        }
                    }
                }
            }
        } header: {
            if manager.teams.count > 1 {
                Picker("Team", selection: $selectedTeam) {
                    Text("All Teams").tag(nil as Team?)
                    ForEach(manager.teams, id: \.identifier) { team in
                        Text(team.name).tag(team as Team?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .navigationTitle("App IDs")
        .task {
            if let team = manager.teams.first {
                await manager.fetchAppIDs(for: team)
            }
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

struct CertificatesView: View {
    @ObservedObject var manager: AppleIDManager
    @State private var selectedTeam: Team?
    
    var body: some View {
        List {
            if manager.certificates.isEmpty {
                Section {
                    Text("No Certificates")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(manager.certificates.indices, id: \.self) { index in
                    let certificate = manager.certificates[index]
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(certificate.name)
                                .font(.headline)
                            Text("Serial: \(certificate.serialNumber)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let machineName = certificate.machineName {
                                Text("Machine: \(machineName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let expirationDate = certificate.expirationDate {
                                Text("Expires: \(expirationDate, formatter: dateFormatter)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Button(role: .destructive) {
                            Task {
                                if let team = selectedTeam ?? manager.teams.first {
                                    await manager.revokeCertificate(certificate, team: team)
                                }
                            }
                        } label: {
                            Text("Revoke Certificate")
                        }
                    }
                }
            }
        } header: {
            if manager.teams.count > 1 {
                Picker("Team", selection: $selectedTeam) {
                    Text("All Teams").tag(nil as Team?)
                    ForEach(manager.teams, id: \.identifier) { team in
                        Text(team.name).tag(team as Team?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .navigationTitle("Certificates")
        .task {
            if let team = manager.teams.first {
                await manager.fetchCertificates(for: team)
            }
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
