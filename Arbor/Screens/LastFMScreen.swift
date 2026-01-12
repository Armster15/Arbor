import SwiftUI
import UIKit
import ScrobbleKit
import SPIndicator

struct LastFMScreen: View {
    @EnvironmentObject private var lastFM: LastFMSession
    
    @State private var profileImageURL: URL? = nil
    @State private var scrobbleCount: Int? = nil
    @State private var isLoadingUserInfo: Bool = false
    @State private var userInfoErrorMessage: String? = nil
    @State private var showLogoutConfirmation: Bool = false
    
    @MainActor
    private func loadUserInfo() async {
        let cacheKey = ["lastfm", "user", lastFM.username]
        
        guard lastFM.isAuthenticated,
              !lastFM.username.isEmpty,
              let manager = lastFM.manager else { return }
        
        if let cached: SBKUser = QueryCache.shared.get(for: cacheKey) {
            scrobbleCount = cached.playcount
            if let url = cached.image?.largestSize {
                profileImageURL = url
            } else {
                profileImageURL = nil
            }
            return
        }
        
        isLoadingUserInfo = true
        userInfoErrorMessage = nil
        defer { isLoadingUserInfo = false }
        
        do {
            let user = try await manager.getInfo(forUser: lastFM.username)
            scrobbleCount = user.playcount
            if let url = user.image?.largestSize {
                profileImageURL = url
            } else {
                profileImageURL = nil
            }
            QueryCache.shared.set(user, for: cacheKey)
        } catch {
            if error is CancellationError { return }
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            userInfoErrorMessage = error.localizedDescription
        }
    }
    
    private func logOut() {
        do {
            try lastFM.signOut()
            profileImageURL = nil
            scrobbleCount = nil
        } catch {
            showAlert(title: "Sign out failed", message: error.localizedDescription)
        }
    }
        
    var body: some View {
        Group {
            if lastFM.isAuthenticated {
                LoggedInLastFMView(
                    username: lastFM.username,
                    profileImageURL: profileImageURL,
                    scrobbleCount: scrobbleCount,
                    isLoadingUserInfo: isLoadingUserInfo,
                    errorMessage: userInfoErrorMessage,
                    onLogoutTapped: {
                        showLogoutConfirmation = true
                    }
                )
                .frame(maxWidth: .infinity, alignment: .top)
            } else {
                ScrollView {
                    VStack {
                        LoggedOutLastFMView()
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.top, 4)
                }
            }
        }
        // runs an async task whenever the id value changes
        .task(id: lastFM.username) {
            await loadUserInfo()
        }
        .onChange(of: lastFM.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                profileImageURL = nil
                scrobbleCount = nil
                userInfoErrorMessage = nil
            }
        }
        .alert("Sign Out?", isPresented: $showLogoutConfirmation) {
            Button("Sign Out", role: .destructive) {
                logOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out of Last.fm?")
        }
    }
}

private struct LoggedInLastFMView: View {
    @EnvironmentObject private var lastFM: LastFMSession
    @Environment(\.colorScheme) var colorScheme
    
    let username: String
    let profileImageURL: URL?
    let scrobbleCount: Int?
    let isLoadingUserInfo: Bool
    let errorMessage: String?
    let onLogoutTapped: () -> Void
    
    private func formattedScrobbleCount() -> String? {
        guard let scrobbleCount else { return nil }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: scrobbleCount)) ?? "\(scrobbleCount)"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            List {
                HStack(alignment: .center, spacing: 8) {
                    ZStack {
                        if let profileImageURL {
                            AsyncImage(url: profileImageURL) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .tint(Color("PrimaryText"))
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    Image("LastFMDefaultAvatar")
                                        .resizable()
                                        .scaledToFill()
                                @unknown default:
                                    Image("LastFMDefaultAvatar")
                                        .resizable()
                                        .scaledToFill()
                                }
                            }
                        } else {
                            Image("LastFMDefaultAvatar")
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(username)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(Color("PrimaryText"))
                        
                        Text(isLoadingUserInfo ? "Loading scrobbles..." : "\(formattedScrobbleCount() ?? "0") scrobbles")
                            .font(.subheadline)
                            .foregroundColor(Color("PrimaryText"))
                            .lineLimit(2)
                    }
                    
                    Spacer()
                }
                .listRowBackground(Color("SecondaryBg"))
                
                if let errorMessage {
                    Text("Couldn’t load Last.fm profile: \(errorMessage)")
                        .foregroundColor(.red)
                        .listRowBackground(Color("SecondaryBg"))
                }

                Toggle(
                    "Enable scrobbling",
                    isOn: Binding(
                        get: { lastFM.isScrobblingEnabled },
                        set: { lastFM.isScrobblingEnabled = $0 }
                    )
                )
                .tint(colorScheme == .light ? Color("PrimaryBg") : .green)
                .listRowBackground(Color("SecondaryBg"))

                Section {
                    Button("Sign Out", role: .destructive) {
                        onLogoutTapped()
                    }
                    .listRowBackground(Color("SecondaryBg"))
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
    }
}

private struct LoggedOutLastFMView: View {
    @EnvironmentObject private var lastFM: LastFMSession
    
    // form input values
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil
    
    private func openInSafari(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    @MainActor
    private func submit() async {        
        guard !username.isEmpty,
              !password.isEmpty,
              !apiKey.isEmpty,
              !apiSecret.isEmpty else {
            showAlert(title: "Missing info", message: "Please fill in all fields")
            return
        }
        
        isSubmitting = true
        errorMessage = nil

        // `defer` guarantees isSubmitting gets set back to false when the function ends, 
        // whether the login succeeds or fails in the catch block
        defer { isSubmitting = false }
        
        do {
            try await lastFM.signIn(
                username: username,
                password: password,
                apiKey: apiKey,
                apiSecret: apiSecret
            )
            SPIndicatorView(title: "Signed in to Last.fm", preset: .done).present()
            
            username = ""
            password = ""
            apiKey = ""
            apiSecret = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .formFieldLabelStyle()

                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.asciiCapable)
                    .formFieldInputStyle()
            }
            .formFieldContainer()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .formFieldLabelStyle()

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.asciiCapable)
                    .formFieldInputStyle()
            }
            .formFieldContainer()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .formFieldLabelStyle()

                TextField("API Key", text: $apiKey)
                    .textContentType(nil)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.asciiCapable)
                    .formFieldInputStyle()
            }
            .formFieldContainer()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("API Secret")
                    .formFieldLabelStyle()

                SecureField("API Secret", text: $apiSecret)
                    .textContentType(nil)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.asciiCapable)
                    .formFieldInputStyle()
            }
            .formFieldContainer()
        }
        
        Spacer(minLength: 48)
        
        if let errorMessage {
            Text("Couldn’t sign in to Last.fm: \(errorMessage)")
                .font(.footnote)
                .foregroundColor(.red)
                .padding(.horizontal)
        }
        
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 12) {
                if isSubmitting {
                    ProgressView()
                }

                Text("Sign In")
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .primaryActionButtonStyle(isLoading: isSubmitting, isDisabled: false)
        
        HStack(spacing: 12) {
            Button {
                openInSafari("https://www.last.fm/api/account/create")
            } label: {
                HStack(spacing: 6) {
                    Text("Create API key")
                    Image(systemName: "arrow.up.forward")
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color("PrimaryText").opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            
            Button {
                openInSafari("https://www.last.fm/api/accounts")
            } label: {
                HStack(spacing: 6) {
                    Text("View API keys")
                    Image(systemName: "arrow.up.forward")
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color("PrimaryText").opacity(0.8))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .tint(Color("SecondaryBg"))
        .padding(.horizontal)
        .padding(.bottom)
    }
}
