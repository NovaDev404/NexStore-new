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

struct AnisetteServer: Identifiable, Codable {
    let id = UUID()
    let name: String
    let address: String
}

struct AnisetteServersResponse: Codable {
    let servers: [AnisetteServer]
}

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
    @Published var requiresTwoFactor = false
    @Published var twoFactorMethod: String = ""
    @Published var anisetteServers: [AnisetteServer] = []
    @Published var selectedAnisetteServer: AnisetteServer?
    
    private let api = AppleAPI.shared
    private var currentVerificationHandler: ((String?) -> Void)?
    
    init() {
        Task {
            await fetchAnisetteServers()
        }
    }
    
    func fetchAnisetteServers() async {
        do {
            let url = URL(string: "https://servers.sidestore.io/servers.json")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AnisetteServersResponse.self, from: data)
            self.anisetteServers = response.servers
            if let firstServer = response.servers.first {
                self.selectedAnisetteServer = firstServer
            }
        } catch {
            // Fallback to default server
            let fallbackServer = AnisetteServer(name: "SideStore", address: "https://ani.sidestore.io")
            self.anisetteServers = [fallbackServer]
            self.selectedAnisetteServer = fallbackServer
        }
    }
    
    func fetchAnisetteData(from server: AnisetteServer) async throws -> AnisetteData {
        guard let url = URL(string: "\(server.address)/v1/anisette") else {
            throw NSError(domain: "AnisetteError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "device": "iPhone14,3",
            "os": "iOS",
            "osVersion": "16.5",
            "model": "iPhone",
            "protocolVersion": "A1234"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "AnisetteError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch anisette data"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let machineID = json?["machineID"] as? String,
              let oneTimePassword = json?["oneTimePassword"] as? String,
              let localUserID = json?["localUserID"] as? String,
              let routingInfoString = json?["routingInfo"] as? String,
              let routingInfo = UInt64(routingInfoString),
              let deviceUniqueIdentifier = json?["deviceUniqueIdentifier"] as? String,
              let deviceSerialNumber = json?["deviceSerialNumber"] as? String,
              let deviceDescription = json?["deviceDescription"] as? String else {
            throw NSError(domain: "AnisetteError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid anisette data response"])
        }
        
        return AnisetteData(
            machineID: machineID,
            oneTimePassword: oneTimePassword,
            localUserID: localUserID,
            routingInfo: routingInfo,
            deviceUniqueIdentifier: deviceUniqueIdentifier,
            deviceSerialNumber: deviceSerialNumber,
            deviceDescription: deviceDescription,
            date: Date(),
            locale: Locale.current,
            timeZone: TimeZone.current
        )
    }
    
    func signIn(appleID: String, password: String) async {
        isLoading = true
        errorMessage = nil
        requiresTwoFactor = false
        
        guard let server = selectedAnisetteServer else {
            errorMessage = "No anisette server selected"
            isLoading = false
            return
        }
        
        do {
            let anisetteData = try await fetchAnisetteData(from: server)
            
            let (account, session) = try await api.authenticate(
                appleID: appleID,
                password: password,
                anisetteData: anisetteData
            ) { verificationHandler in
                Task { @MainActor in
                    self.requiresTwoFactor = true
                    self.twoFactorMethod = "SMS"
                    self.currentVerificationHandler = verificationHandler
                }
            }
            
            self.account = account
            self.session = session
            self.isSignedIn = true
            self.requiresTwoFactor = false
            self.currentVerificationHandler = nil
            
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
            self.requiresTwoFactor = false
            self.currentVerificationHandler = nil
        }
        
        isLoading = false
    }
    
    func submitTwoFactorCode(_ code: String) async {
        isLoading = true
        errorMessage = nil
        
        currentVerificationHandler?(code)
        
        // Wait a bit for authentication to complete
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
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
    @State private var twoFactorCode = ""
    @State private var showingSignIn = true
    @State private var showingTwoFactor = false
    
    var body: some View {
        NBNavigationView(.localized("Apple ID")) {
            if showingTwoFactor {
                twoFactorView
            } else if showingSignIn || !manager.isSignedIn {
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
                Picker("Anisette Server", selection: $manager.selectedAnisetteServer) {
                    ForEach(manager.anisetteServers) { server in
                        Text(server.name).tag(server as AnisetteServer?)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Anisette Server")
            } footer: {
                Text("Select an anisette server to authenticate with Apple.")
            }
            
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
                        await manager.signIn(appleID: appleID, password: password)
                        
                        if manager.requiresTwoFactor {
                            showingTwoFactor = true
                        } else if manager.isSignedIn {
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
                .disabled(manager.isLoading || appleID.isEmpty || password.isEmpty || manager.selectedAnisetteServer == nil)
            }
        }
        .navigationTitle("Apple ID")
    }
    
    private var twoFactorView: some View {
        Form {
            Section {
                Text("Enter the \(manager.twoFactorMethod) verification code sent to your device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Section {
                TextField("Verification Code", text: $twoFactorCode)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
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
                        await manager.submitTwoFactorCode(twoFactorCode)
                        
                        if manager.isSignedIn {
                            showingTwoFactor = false
                            showingSignIn = false
                            twoFactorCode = ""
                        }
                    }
                }) {
                    HStack {
                        if manager.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Verify")
                    }
                }
                .disabled(manager.isLoading || twoFactorCode.isEmpty)
            }
        }
        .navigationTitle("Two-Factor Authentication")
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
