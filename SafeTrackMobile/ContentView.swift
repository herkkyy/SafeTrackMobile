//
//  ContentView.swift
//  SafeTrackMobile
//
//  Mobile-First Redesign for SafeTrack
//  Inspired by clean mobile ergonomics (Floating Center '+' Action, Curved Header, Progress Slider)
//  Integrated with SafeTrack Laravel REST API (Sanctum)
//

import SwiftUI
import Combine

// MARK: - ==========================================
// MARK: 1. DATA MODELS & BACKEND DTOs
// MARK: - ==========================================

struct ApiResponse<T: Codable>: Codable {
    let status: String
    let message: String?
    let data: T?
}

struct LoginPayload: Codable {
    let token: String
    let tokenType: String
    let user: UserProfile

    enum CodingKeys: String, CodingKey {
        case token
        case tokenType = "token_type"
        case user
    }
}

struct UserProfile: Codable, Identifiable {
    let id: Int
    let name: String
    let username: String
    let email: String
    let role: String
    let department: DepartmentInfo?
    let employeeRegistry: EmployeeRegistryInfo?

    enum CodingKeys: String, CodingKey {
        case id, name, username, email, role, department
        case employeeRegistry = "employee_registry"
    }
}

struct DepartmentInfo: Codable {
    let id: Int
    let name: String
    let isHse: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case isHse = "is_hse"
    }
}

struct EmployeeRegistryInfo: Codable {
    let nik: String
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case nik
        case fullName = "full_name"
    }
}

struct SapSummaryData: Codable {
    let period: String
    let periodFormatted: String
    let isHse: Bool
    let stats: SapStats
    let conversion: SapConversion
    let calculatedAt: String?

    enum CodingKeys: String, CodingKey {
        case period
        case periodFormatted = "period_formatted"
        case isHse = "is_hse"
        case stats, conversion
        case calculatedAt = "calculated_at"
    }
}

struct SapStats: Codable {
    let hazardCount: Int
    let inspectionCount: Int
    let safetyTalkCount: Int
    let resolutionCount: Int
    let totalPoints: Int

    enum CodingKeys: String, CodingKey {
        case hazardCount = "hazard_count"
        case inspectionCount = "inspection_count"
        case safetyTalkCount = "safety_talk_count"
        case resolutionCount = "resolution_count"
        case totalPoints = "total_points"
    }
}

struct SapConversion: Codable {
    let type: String
    let targetMet: Bool?
    let targetMetLabel: String?
    let rewardEligible: Bool
    let reward: RewardInfo?

    enum CodingKeys: String, CodingKey {
        case type
        case targetMet = "target_met"
        case targetMetLabel = "target_met_label"
        case rewardEligible = "reward_eligible"
        case reward
    }
}

struct RewardInfo: Codable {
    let id: Int
    let name: String
    let requiredPoints: Int
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case requiredPoints = "required_points"
    }
}

// Mobile Domain Items
struct HazardItem: Identifiable {
    let id: String
    var title: String
    var location: String
    var time: String
    var risk: String
    var status: String
    var reporter: String
}

struct InspectionItem: Identifiable {
    let id: String
    var area: String
    var shift: String
    var status: String
    var date: String
}

// MARK: - ==========================================
// MARK: 2. API SERVICE
// MARK: - ==========================================

final class APIService {
    static let shared = APIService()
    var baseURL: String = "http://127.0.0.1:8000/api"

    private init() {}

    func login(login: String, password: String) async throws -> (token: String, user: UserProfile) {
        guard let url = URL(string: "\(baseURL)/login") else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = ["login": login, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if httpResponse.statusCode == 200 {
            let decoded = try JSONDecoder().decode(ApiResponse<LoginPayload>.self, from: data)
            guard let payload = decoded.data else {
                throw NSError(domain: "SafeTrack", code: 500, userInfo: [NSLocalizedDescriptionKey: "Data login tidak valid"])
            }
            return (payload.token, payload.user)
        } else {
            if let errorObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorObj["message"] as? String {
                throw NSError(domain: "SafeTrack", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "SafeTrack", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gagal login (\(httpResponse.statusCode))"])
        }
    }

    func fetchSapSummary(token: String) async throws -> SapSummaryData {
        guard let url = URL(string: "\(baseURL)/sap/summary") else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if httpResponse.statusCode == 200 {
            let decoded = try JSONDecoder().decode(ApiResponse<SapSummaryData>.self, from: data)
            guard let summary = decoded.data else {
                throw NSError(domain: "SafeTrack", code: 500, userInfo: [NSLocalizedDescriptionKey: "Data SAP kosong"])
            }
            return summary
        } else {
            throw NSError(domain: "SafeTrack", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gagal memuat ringkasan SAP"])
        }
    }

    func logout(token: String) async {
        guard let url = URL(string: "\(baseURL)/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }
}

// MARK: - ==========================================
// MARK: 3. APP VIEW MODEL
// MARK: - ==========================================

@MainActor
final class AppViewModel: ObservableObject {
    @Published var currentUser: UserProfile?
    @Published var authToken: String?
    @Published var sapSummary: SapSummaryData?

    // Navigation
    @Published var selectedTab: MobileTab = .beranda
    @Published var selectedPeriod: String = "Hari Ini"

    // Dialogs & Sheets
    @Published var showQuickHazardSheet: Bool = false
    @Published var showNotificationSheet: Bool = false
    @Published var showLogoutAlert: Bool = false

    // State
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showErrorAlert: Bool = false

    // Hazard Report Items (Realtime in-app collection)
    @Published var hazards: [HazardItem] = [
        HazardItem(id: "HZ-101", title: "Kabel terkelupas di area produksi", location: "Werehouse B-02", time: "08:30 Pagi", risk: "Sedang", status: "Proses", reporter: "Kevin Anggara"),
        HazardItem(id: "HZ-102", title: "Toren air bocor membasahi jalur forklift", location: "Fuel Storage", time: "10:15 Pagi", risk: "Tinggi", status: "Sedang Ditangani", reporter: "Kevin Anggara"),
        HazardItem(id: "HZ-103", title: "Plang rambu evakuasi miring", location: "Jalan Utama Area 1", time: "Kemarin", risk: "Rendah", status: "Selesai", reporter: "Prans"),
        HazardItem(id: "HZ-104", title: "Ceceran oli di lantai kerja", location: "Fabrikasi 3", time: "Kemarin", risk: "Sedang", status: "Selesai", reporter: "Pengguna")
    ]

    // Inspections
    @Published var inspections: [InspectionItem] = [
        InspectionItem(id: "INS-01", area: "Werehouse Utama", shift: "Shift Pagi", status: "Menunggu Review", date: "Hari Ini"),
        InspectionItem(id: "INS-02", area: "Workshop Mekanikal", shift: "Shift Siang", status: "Selesai", date: "Kemarin")
    ]

    private let tokenKey = "safetrack_auth_token"
    private let userKey = "safetrack_user_data"

    init() {
        loadPersistedSession()
    }

    var isAuthenticated: Bool {
        authToken != nil && currentUser != nil
    }

    func login(username: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let (token, user) = try await APIService.shared.login(login: username, password: password)
            self.authToken = token
            self.currentUser = user
            saveSession(token: token, user: user)

            await loadSapSummary()
            isLoading = false
        } catch {
            isLoading = false
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
        }
    }

    func loadSapSummary() async {
        guard let token = authToken else { return }
        do {
            let summary = try await APIService.shared.fetchSapSummary(token: token)
            self.sapSummary = summary
        } catch {
            // Keep existing or calculate
        }
    }

    func refreshData() async {
        await loadSapSummary()
    }

    func logout() async {
        if let token = authToken {
            await APIService.shared.logout(token: token)
        }
        self.authToken = nil
        self.currentUser = nil
        self.sapSummary = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    func submitNewHazard(title: String, location: String, risk: String) {
        let newHazard = HazardItem(
            id: "HZ-\(Int.random(in: 200...999))",
            title: title,
            location: location,
            time: "Baru saja",
            risk: risk,
            status: "Proses",
            reporter: currentUser?.name ?? "Saya"
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            hazards.insert(newHazard, at: 0)
        }
    }

    private func saveSession(token: String, user: UserProfile) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: userKey)
        }
    }

    private func loadPersistedSession() {
        if let token = UserDefaults.standard.string(forKey: tokenKey),
           let userData = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(UserProfile.self, from: userData) {
            self.authToken = token
            self.currentUser = user
            Task {
                await loadSapSummary()
            }
        }
    }
}

// MARK: - ==========================================
// MARK: 4. DESIGN TOKENS (SafeTrack Mobile Palette)
// MARK: - ==========================================

enum MobileTab: String, CaseIterable {
    case beranda = "Beranda"
    case bahaya = "Bahaya"
    case inspeksi = "Inspeksi"
    case profile = "Profile"

    var icon: String {
        switch self {
        case .beranda: return "house.fill"
        case .bahaya: return "exclamationmark.triangle.fill"
        case .inspeksi: return "list.clipboard.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

enum SafeTrackTheme {
    // Brand Colors
    static let primaryNavy = Color(red: 15/255, green: 42/255, blue: 74/255)       // #0F2A4A
    static let deepNavy = Color(red: 7/255, green: 25/255, blue: 47/255)          // #07192F
    static let headerGradient = LinearGradient(
        colors: [Color(red: 15/255, green: 42/255, blue: 74/255), Color(red: 23/255, green: 65/255, blue: 110/255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Accents
    static let accentGold = Color(red: 245/255, green: 158/255, blue: 11/255)     // #F59E0B
    static let amberDark = Color(red: 217/255, green: 119/255, blue: 6/255)       // #D97706
    static let amberBg = Color(red: 254/255, green: 243/255, blue: 199/255)       // #FEF3C7
    
    // Neutrals
    static let background = Color(red: 245/255, green: 247/255, blue: 250/255)    // Clean light grey
    static let cardBg = Color.white
    static let borderLight = Color(red: 229/255, green: 231/255, blue: 235/255)   // #E5E7EB
    static let textHeading = Color(red: 17/255, green: 24/255, blue: 39/255)      // #111827
    static let textBody = Color(red: 75/255, green: 85/255, blue: 99/255)         // #4B5563
    static let textMuted = Color(red: 156/255, green: 163/255, blue: 175/255)    // #9CA3AF

    // Status Badges
    static let blueBg = Color(red: 224/255, green: 242/255, blue: 254/255)        // #E0F2FE
    static let blueText = Color(red: 2/255, green: 132/255, blue: 199/255)        // #0284C7
    static let greenBg = Color(red: 220/255, green: 252/255, blue: 231/255)       // #DCFCE7
    static let greenText = Color(red: 22/255, green: 163/255, blue: 74/255)       // #16A34A
    static let redBg = Color(red: 254/255, green: 226/255, blue: 226/255)         // #FEE2E2
    static let redText = Color(red: 220/255, green: 38/255, blue: 38/255)         // #DC2626
}

// MARK: - ==========================================
// MARK: 5. MAIN CONTENT VIEW
// MARK: - ==========================================

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        Group {
            if viewModel.isAuthenticated {
                MobileMainLayoutView(viewModel: viewModel)
            } else {
                MobileLoginView(viewModel: viewModel)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isAuthenticated)
        .alert("Informasi SafeTrack", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Terjadi kesalahan")
        }
    }
}

// MARK: - ==========================================
// MARK: 6. MAIN MOBILE LAYOUT (With Raised '+' FAB)
// MARK: - ==========================================

struct MobileMainLayoutView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            SafeTrackTheme.background
                .ignoresSafeArea()

            // Active Tab Content
            Group {
                switch viewModel.selectedTab {
                case .beranda:
                    HomeSimpleTabView(viewModel: viewModel)
                case .bahaya:
                    HazardSimpleTabView(viewModel: viewModel)
                case .inspeksi:
                    InspectionSimpleTabView(viewModel: viewModel)
                case .profile:
                    ProfileSimpleTabView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom Floating Bottom Navigation Bar
            CustomFloatingTabBar(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showQuickHazardSheet) {
            QuickHazardReportSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showNotificationSheet) {
            NotificationSheetView()
        }
    }
}

// MARK: - ==========================================
// MARK: 7. FLOATING BOTTOM BAR WITH CENTER '+' FAB
// MARK: - ==========================================

struct CustomFloatingTabBar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack(alignment: .top) {
            // Tab Bar Background Container
            HStack(spacing: 0) {
                // Tab 1: Beranda
                TabBarItemButton(
                    tab: .beranda,
                    isSelected: viewModel.selectedTab == .beranda
                ) {
                    viewModel.selectedTab = .beranda
                }

                // Tab 2: Bahaya
                TabBarItemButton(
                    tab: .bahaya,
                    isSelected: viewModel.selectedTab == .bahaya
                ) {
                    viewModel.selectedTab = .bahaya
                }

                // Spacer for the center raised button
                Spacer()
                    .frame(width: 68)

                // Tab 3: Inspeksi
                TabBarItemButton(
                    tab: .inspeksi,
                    isSelected: viewModel.selectedTab == .inspeksi
                ) {
                    viewModel.selectedTab = .inspeksi
                }

                // Tab 4: Profile
                TabBarItemButton(
                    tab: .profile,
                    isSelected: viewModel.selectedTab == .profile
                ) {
                    viewModel.selectedTab = .profile
                }
            }
            .frame(height: 64)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.08), radius: 14, y: 4)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Raised Center '+' Floating Action Button (FAB)
            Button {
                viewModel.showQuickHazardSheet = true
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [SafeTrackTheme.accentGold, SafeTrackTheme.amberDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)
                        .shadow(color: SafeTrackTheme.accentGold.opacity(0.4), radius: 10, y: 5)

                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .offset(y: -22) // Raised above the tab bar
        }
    }
}

struct TabBarItemButton: View {
    let tab: MobileTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? SafeTrackTheme.primaryNavy : SafeTrackTheme.textMuted)

                Text(tab.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? SafeTrackTheme.primaryNavy : SafeTrackTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - ==========================================
// MARK: 8. TAB 1: BERANDA (HOME - CLEAN & SIMPLE)
// MARK: - ==========================================

struct HomeSimpleTabView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Curved Gradient Header matching reference
                CurvedHeaderView(viewModel: viewModel)

                // Period Filter Pills (Hari Ini, Minggu Ini, Bulan Ini)
                PeriodFilterPills(selectedPeriod: $viewModel.selectedPeriod)
                    .padding(.horizontal, 20)

                // Main Progress Card (SAP Points & Progress Slider)
                SapProgressCard(viewModel: viewModel)
                    .padding(.horizontal, 20)

                // Today's Activity & Hazards List (Timeline style)
                TodayHazardsSection(viewModel: viewModel)
                    .padding(.horizontal, 20)

                // Space for floating tab bar
                Spacer(minLength: 90)
            }
        }
        .ignoresSafeArea(edges: .top)
        .refreshable {
            await viewModel.refreshData()
        }
    }
}

struct CurvedHeaderView: View {
    @ObservedObject var viewModel: AppViewModel

    var greetingTime: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return "Pagi" }
        if hour < 15 { return "Siang" }
        if hour < 18 { return "Sore" }
        return "Malam"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Curved Gradient
            SafeTrackTheme.headerGradient
                .clipShape(CustomBottomCurvedShape(curveOffset: 26))

            VStack(alignment: .leading, spacing: 14) {
                // Top Row: User Greeting & Icons
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Halo, Selamat \(greetingTime)!")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.85))

                        HStack(spacing: 4) {
                            Text(viewModel.currentUser?.name ?? "Karyawan SafeTrack")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.8))
                        }
                    }

                    Spacer()

                    // Action Icons
                    HStack(spacing: 10) {
                        Button {
                            viewModel.showNotificationSheet = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 38, height: 38)

                                Image(systemName: "bell.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .frame(width: 38, height: 38)

                                // Red indicator dot
                                Circle()
                                    .fill(SafeTrackTheme.accentGold)
                                    .frame(width: 8, height: 8)
                                    .offset(x: -4, y: 4)
                            }
                        }

                        Button {
                            viewModel.selectedTab = .profile
                        } label: {
                            Circle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                }
                .padding(.top, 56)

                // Hero Headline
                Text("Status K3 Hari Ini!")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 200)
    }
}

struct CustomBottomCurvedShape: Shape {
    var curveOffset: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - curveOffset))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height - curveOffset),
            control: CGPoint(x: rect.width / 2, y: rect.height + curveOffset)
        )
        path.closeSubpath()
        return path
    }
}

struct PeriodFilterPills: View {
    @Binding var selectedPeriod: String
    let periods = ["Hari Ini", "Minggu Ini", "Bulan Ini"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(periods, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedPeriod = item
                    }
                } label: {
                    Text(item)
                        .font(.system(size: 13, weight: selectedPeriod == item ? .bold : .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedPeriod == item ? SafeTrackTheme.primaryNavy : Color.white)
                        .foregroundColor(selectedPeriod == item ? .white : SafeTrackTheme.textBody)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(selectedPeriod == item ? Color.clear : SafeTrackTheme.borderLight, lineWidth: 1)
                        )
                }
            }
            Spacer()
        }
    }
}

// MARK: - ==========================================
// MARK: 9. HERO PROGRESS CARD (SAP SLIDER)
// MARK: - ==========================================

struct SapProgressCard: View {
    @ObservedObject var viewModel: AppViewModel

    var points: Int {
        viewModel.sapSummary?.stats.totalPoints ?? 2
    }
    var targetPoints: Int { 10 }
    var percentage: Int {
        min(100, Int((Double(points) / Double(targetPoints)) * 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(points)/\(targetPoints) Poin SAP Terkumpul")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(SafeTrackTheme.textHeading)

                    if let reward = viewModel.sapSummary?.conversion.reward {
                        Text("🎁 Menuju: \(reward.name)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SafeTrackTheme.amberDark)
                    } else if viewModel.currentUser?.department?.isHse == true {
                        Text("🎯 Target KPI Keselamatan Bulanan")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SafeTrackTheme.greenText)
                    } else {
                        Text("Terus laporkan bahaya untuk klaim hadiah K3!")
                            .font(.system(size: 12))
                            .foregroundColor(SafeTrackTheme.textMuted)
                    }
                }

                Spacer()

                // Small badge
                Text("\(percentage)%")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(SafeTrackTheme.primaryNavy)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SafeTrackTheme.blueBg)
                    .cornerRadius(10)
            }

            // Sleek Progress Bar Slider
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .systemGray5))
                        .frame(height: 12)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [SafeTrackTheme.accentGold, SafeTrackTheme.amberDark],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(16, geo.size.width * CGFloat(Double(percentage) / 100.0)), height: 12)
                }
            }
            .frame(height: 12)

            // 4 Mini Indicators
            HStack {
                MiniStatLabel(label: "Bahaya", count: viewModel.sapSummary?.stats.hazardCount ?? 2)
                Spacer()
                MiniStatLabel(label: "Inspeksi", count: viewModel.sapSummary?.stats.inspectionCount ?? 1)
                Spacer()
                MiniStatLabel(label: "Talk", count: viewModel.sapSummary?.stats.safetyTalkCount ?? 0)
                Spacer()
                MiniStatLabel(label: "Selesai", count: viewModel.sapSummary?.stats.resolutionCount ?? 1)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(SafeTrackTheme.cardBg)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(SafeTrackTheme.borderLight, lineWidth: 1))
    }
}

struct MiniStatLabel: View {
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(SafeTrackTheme.primaryNavy.opacity(0.2))
                .frame(width: 6, height: 6)
            Text("\(label):")
                .font(.system(size: 11))
                .foregroundColor(SafeTrackTheme.textMuted)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(SafeTrackTheme.textHeading)
        }
    }
}

// MARK: - ==========================================
// MARK: 10. TODAY'S HAZARDS TIMELINE SECTION
// MARK: - ==========================================

struct TodayHazardsSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Laporan Bahaya Hari Ini")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(SafeTrackTheme.textHeading)

                Spacer()

                Button {
                    viewModel.selectedTab = .bahaya
                } label: {
                    Text("Lihat Semua")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SafeTrackTheme.primaryNavy)
                }
            }

            // Clean Vertical Cards
            VStack(spacing: 10) {
                ForEach(viewModel.hazards.prefix(3)) { item in
                    SimpleHazardCardRow(item: item)
                }
            }
        }
    }
}

struct SimpleHazardCardRow: View {
    let item: HazardItem

    var body: some View {
        HStack(spacing: 14) {
            // Time Badge Column
            VStack(alignment: .leading, spacing: 2) {
                Text(item.time)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(SafeTrackTheme.textHeading)
                Text(item.location)
                    .font(.system(size: 10))
                    .foregroundColor(SafeTrackTheme.textMuted)
                    .lineLimit(1)
            }
            .frame(width: 85, alignment: .leading)

            Divider()
                .frame(height: 36)

            // Title & Risk
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SafeTrackTheme.textHeading)
                    .lineLimit(1)

                Text("Pelapor: \(item.reporter)")
                    .font(.system(size: 10))
                    .foregroundColor(SafeTrackTheme.textMuted)
            }

            Spacer()

            // Status Pill
            Text(item.status)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusBg(item.status))
                .foregroundColor(statusColor(item.status))
                .cornerRadius(8)
        }
        .padding(14)
        .background(SafeTrackTheme.cardBg)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.02), radius: 8, y: 2)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SafeTrackTheme.borderLight, lineWidth: 1))
    }

    private func statusBg(_ status: String) -> Color {
        if status == "Selesai" { return SafeTrackTheme.greenBg }
        if status == "Sedang Ditangani" { return SafeTrackTheme.amberBg }
        return SafeTrackTheme.blueBg
    }

    private func statusColor(_ status: String) -> Color {
        if status == "Selesai" { return SafeTrackTheme.greenText }
        if status == "Sedang Ditangani" { return SafeTrackTheme.amberDark }
        return SafeTrackTheme.blueText
    }
}

// MARK: - ==========================================
// MARK: 11. TAB 2: BAHAYA (ALL HAZARDS LIST)
// MARK: - ==========================================

struct HazardSimpleTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var filterText: String = ""

    var filteredList: [HazardItem] {
        if filterText.isEmpty { return viewModel.hazards }
        return viewModel.hazards.filter { $0.title.localizedCaseInsensitiveContains(filterText) || $0.location.localizedCaseInsensitiveContains(filterText) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Top Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Laporan Bahaya")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(SafeTrackTheme.textHeading)
                    Text("Pantau seluruh potensi bahaya dan tindak lanjutnya.")
                        .font(.system(size: 13))
                        .foregroundColor(SafeTrackTheme.textMuted)
                }
                .padding(.top, 56)
                .padding(.horizontal, 20)

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(SafeTrackTheme.textMuted)
                    TextField("Cari temuan atau lokasi...", text: $filterText)
                        .font(.subheadline)
                }
                .padding(12)
                .background(Color.white)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(SafeTrackTheme.borderLight, lineWidth: 1))
                .padding(.horizontal, 20)

                // List
                VStack(spacing: 12) {
                    ForEach(filteredList) { item in
                        SimpleHazardCardRow(item: item)
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 90)
            }
        }
    }
}

// MARK: - ==========================================
// MARK: 12. TAB 3: INSPEKSI (DAILY INSPECTIONS)
// MARK: - ==========================================

struct InspectionSimpleTabView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inspeksi Harian")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(SafeTrackTheme.textHeading)
                    Text("Pastikan area kerja aman sebelum memulai shift.")
                        .font(.system(size: 13))
                        .foregroundColor(SafeTrackTheme.textMuted)
                }
                .padding(.top, 56)
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    ForEach(viewModel.inspections) { ins in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ins.area)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(SafeTrackTheme.textHeading)
                                Text("\(ins.shift) · \(ins.date)")
                                    .font(.system(size: 12))
                                    .foregroundColor(SafeTrackTheme.textMuted)
                            }
                            Spacer()
                            Text(ins.status)
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(SafeTrackTheme.amberBg)
                                .foregroundColor(SafeTrackTheme.amberDark)
                                .cornerRadius(8)
                        }
                        .padding(16)
                        .background(SafeTrackTheme.cardBg)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SafeTrackTheme.borderLight, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 90)
            }
        }
    }
}

// MARK: - ==========================================
// MARK: 13. TAB 4: PROFILE
// MARK: - ==========================================

struct ProfileSimpleTabView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Header Profile Avatar
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(SafeTrackTheme.primaryNavy.opacity(0.1))
                            .frame(width: 80, height: 80)

                        Text(viewModel.currentUser?.name.prefix(1).uppercased() ?? "K")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(SafeTrackTheme.primaryNavy)
                    }

                    Text(viewModel.currentUser?.name ?? "Karyawan")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(SafeTrackTheme.textHeading)

                    Text(viewModel.currentUser?.department?.name ?? "Operasional")
                        .font(.system(size: 13))
                        .foregroundColor(SafeTrackTheme.textMuted)
                }
                .padding(.top, 60)

                // Info Details Card
                VStack(spacing: 12) {
                    ProfileRow(icon: "person.text.rectangle", title: "NIK", value: viewModel.currentUser?.employeeRegistry?.nik ?? "DEMO003")
                    Divider()
                    ProfileRow(icon: "building.2", title: "Departemen", value: viewModel.currentUser?.department?.name ?? "Operasional")
                    Divider()
                    ProfileRow(icon: "envelope", title: "Email", value: viewModel.currentUser?.email ?? "karyawan@safetrack.test")
                    Divider()
                    ProfileRow(icon: "server.rack", title: "API Server", value: APIService.shared.baseURL)
                }
                .padding(16)
                .background(SafeTrackTheme.cardBg)
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(SafeTrackTheme.borderLight, lineWidth: 1))
                .padding(.horizontal, 20)

                // Logout Button
                Button {
                    viewModel.showLogoutAlert = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Keluar (Logout)")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(SafeTrackTheme.redText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SafeTrackTheme.redBg)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 90)
            }
        }
        .confirmationDialog("Keluar dari Akun?", isPresented: $viewModel.showLogoutAlert, titleVisibility: .visible) {
            Button("Keluar", role: .destructive) {
                Task {
                    await viewModel.logout()
                }
            }
            Button("Batal", role: .cancel) {}
        }
    }
}

struct ProfileRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(SafeTrackTheme.primaryNavy)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(SafeTrackTheme.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SafeTrackTheme.textHeading)
        }
    }
}

// MARK: - ==========================================
// MARK: 14. QUICK HAZARD REPORT SHEET (TRIGGERED BY '+')
// MARK: - ==========================================

struct QuickHazardReportSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var location: String = "Werehouse"
    @State private var risk: String = "Sedang"

    let locations = ["Werehouse", "Area Fabrikasi", "Fuel Storage", "Workshop", "Jalan Utama"]
    let risks = ["Rendah", "Sedang", "Tinggi"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header text
                    Text("Laporkan potensi bahaya dengan cepat untuk menjaga keselamatan kerja.")
                        .font(.system(size: 13))
                        .foregroundColor(SafeTrackTheme.textMuted)

                    // Form
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Judul Temuan Bahaya *")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(SafeTrackTheme.textHeading)
                            TextField("Contoh: Kabel terkelupas, oli bocor...", text: $title)
                                .padding(12)
                                .background(Color(uiColor: .systemGray6))
                                .cornerRadius(12)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Lokasi Temuan *")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(SafeTrackTheme.textHeading)
                            Picker("Lokasi", selection: $location) {
                                ForEach(locations, id: \.self) { loc in
                                    Text(loc).tag(loc)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .systemGray6))
                            .cornerRadius(12)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tingkat Risiko *")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(SafeTrackTheme.textHeading)
                            Picker("Risiko", selection: $risk) {
                                ForEach(risks, id: \.self) { r in
                                    Text(r).tag(r)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(SafeTrackTheme.borderLight, lineWidth: 1))

                    // Submit Button
                    Button {
                        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        viewModel.submitNewHazard(title: title, location: location, risk: risk)
                        dismiss()
                    } label: {
                        Text("Kirim Laporan Bahaya")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(title.isEmpty ? SafeTrackTheme.primaryNavy.opacity(0.5) : SafeTrackTheme.primaryNavy)
                            .cornerRadius(14)
                    }
                    .disabled(title.isEmpty)
                }
                .padding(20)
            }
            .navigationTitle("Lapor Bahaya")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ==========================================
// MARK: 15. NOTIFICATION SHEET
// MARK: - ==========================================

struct NotificationSheetView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Hari Ini")) {
                    NotificationRow(
                        title: "Poin SAP Bertambah +2 Poin",
                        desc: "Pencapaian SAP bulan Oktober telah diperbarui otomatis.",
                        time: "10:00"
                    )
                    NotificationRow(
                        title: "Laporan Kabel Terkelupas Diverifikasi",
                        desc: "Tim HSE telah mengonfirmasi laporan Anda.",
                        time: "08:30"
                    )
                }

                Section(header: Text("Kemarin")) {
                    NotificationRow(
                        title: "Pengumuman Safety Talk Baru",
                        desc: "Penggunaan APD di Area Produksi.",
                        time: "14:00"
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Notifikasi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Selesai") { dismiss() }
                }
            }
        }
    }
}

struct NotificationRow: View {
    let title: String
    let desc: String
    let time: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(SafeTrackTheme.textHeading)
                Spacer()
                Text(time)
                    .font(.caption2)
                    .foregroundColor(SafeTrackTheme.textMuted)
            }
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(SafeTrackTheme.textBody)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ==========================================
// MARK: 16. MOBILE LOGIN VIEW (Clean & Minimal)
// MARK: - ==========================================

struct MobileLoginView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var loginInput: String = "karyawan"
    @State private var passwordInput: String = "DemoOnly!2026"
    @State private var isPasswordVisible: Bool = false

    var body: some View {
        ZStack {
            SafeTrackTheme.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Brand Emblem
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(SafeTrackTheme.primaryNavy)
                            .frame(width: 72, height: 72)
                            .shadow(color: SafeTrackTheme.primaryNavy.opacity(0.3), radius: 10, y: 5)

                        Image(systemName: "shield.checkerboard")
                            .font(.system(size: 34))
                            .foregroundColor(SafeTrackTheme.accentGold)
                    }

                    Text("SafeTrack")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(SafeTrackTheme.textHeading)

                    Text("Sistem Manajemen Keselamatan Kerja & SAP")
                        .font(.system(size: 12))
                        .foregroundColor(SafeTrackTheme.textMuted)
                }

                // Card
                VStack(spacing: 14) {
                    TextField("Username atau Email", text: $loginInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(14)
                        .background(Color(uiColor: .systemGray6))
                        .cornerRadius(12)

                    HStack {
                        if isPasswordVisible {
                            TextField("Password", text: $passwordInput)
                        } else {
                            SecureField("Password", text: $passwordInput)
                        }
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundColor(SafeTrackTheme.textMuted)
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(12)

                    // Quick Demo Switchers
                    HStack(spacing: 8) {
                        Button("Demo Karyawan") {
                            loginInput = "karyawan"
                            passwordInput = "DemoOnly!2026"
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SafeTrackTheme.amberBg)
                        .foregroundColor(SafeTrackTheme.amberDark)
                        .cornerRadius(8)

                        Button("Demo Admin HSE") {
                            loginInput = "admin"
                            passwordInput = "DemoOnly!2026"
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SafeTrackTheme.blueBg)
                        .foregroundColor(SafeTrackTheme.blueText)
                        .cornerRadius(8)
                    }
                    .padding(.top, 4)

                    // Login Action
                    Button {
                        Task {
                            await viewModel.login(username: loginInput, password: passwordInput)
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Masuk")
                                    .font(.system(size: 16, weight: .bold))
                                Image(systemName: "arrow.right")
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SafeTrackTheme.primaryNavy)
                        .cornerRadius(12)
                    }
                    .disabled(viewModel.isLoading)
                    .padding(.top, 6)
                }
                .padding(20)
                .background(Color.white)
                .cornerRadius(22)
                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 22)

                Spacer()
            }
        }
    }
}

#Preview {
    ContentView()
}
