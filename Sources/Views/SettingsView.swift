import SwiftUI

struct SettingsView: View {
    @AppStorage("fontSize") private var fontSize: Double = 13
    @AppStorage("theme") private var themeRaw: String = TerminalTheme.midnight.rawValue
    @State private var knownCount = KnownHosts.all().count
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("터미널") {
                    Picker("테마", selection: $themeRaw) {
                        ForEach(TerminalTheme.allCases) { t in Text(t.title).tag(t.rawValue) }
                    }
                    VStack(alignment: .leading) {
                        Text("글자 크기: \(Int(fontSize))pt")
                        Slider(value: $fontSize, in: 8...28, step: 1)
                    }
                    preview
                }
                Section {
                    LabeledContent("저장된 서버 키", value: "\(knownCount)개")
                    Button("서버 키 모두 초기화", role: .destructive) { confirmReset = true }
                } header: {
                    Text("보안")
                } footer: {
                    Text("서버를 재설치해서 키가 바뀐 경우 초기화하세요.")
                }
                Section("정보") {
                    LabeledContent("버전", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                    LabeledContent("터미널 엔진", value: "SwiftTerm")
                    LabeledContent("SSH 엔진", value: "Citadel (SwiftNIO SSH)")
                }
            }
            .navigationTitle("설정")
            .onAppear { knownCount = KnownHosts.all().count }
            .confirmationDialog("모든 서버 키를 삭제할까요?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    KnownHosts.removeAll()
                    knownCount = 0
                }
            }
        }
    }

    private var preview: some View {
        let t = TerminalTheme(rawValue: themeRaw) ?? .midnight
        return VStack(alignment: .leading, spacing: 2) {
            Text("user@server:~$ ls -la").foregroundColor(Color(hex: t.colors.fg))
            Text("drwxr-xr-x  5 user  staff  160 .").foregroundColor(Color(hex: t.colors.fg).opacity(0.8))
            Text("▌").foregroundColor(Color(hex: t.colors.caret))
        }
        .font(.system(size: fontSize, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(hex: t.colors.bg))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
