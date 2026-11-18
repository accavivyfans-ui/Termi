import SwiftUI

struct SettingsView: View {
    @AppStorage("fontSize") private var fontSize: Double = 13
    @AppStorage("theme") private var themeRaw: String = TerminalTheme.midnight.rawValue
    @AppStorage("keepAlive") private var keepAlive = true
    @State private var knownCount = KnownHosts.all().count
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("터미널") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(TerminalTheme.allCases) { t in
                                Button { themeRaw = t.rawValue } label: {
                                    VStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color(hex: t.colors.bg))
                                            .frame(width: 64, height: 44)
                                            .overlay(alignment: .topLeading) {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Capsule().fill(Color(hex: t.colors.fg)).frame(width: 30, height: 3)
                                                    Capsule().fill(Color(hex: t.colors.caret)).frame(width: 18, height: 3)
                                                }
                                                .padding(8)
                                            }
                                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(themeRaw == t.rawValue ? Color.accent : Color.hairline,
                                                        lineWidth: themeRaw == t.rawValue ? 2 : 1))
                                        Text(t.title).font(.caption2)
                                            .foregroundStyle(themeRaw == t.rawValue ? .white : Color.textDim)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    VStack(alignment: .leading) {
                        Text("글자 크기: \(Int(fontSize))pt")
                        Slider(value: $fontSize, in: 8...28, step: 1)
                    }
                    preview
                }
                .listRowBackground(Color.panel)
                Section {
                    Toggle("백그라운드에서 연결 유지", isOn: $keepAlive)
                } header: {
                    Text("연결")
                } footer: {
                    Text("다른 앱으로 넘어가도 SSH 세션과 실행 중인 작업이 끊기지 않습니다. 세션이 열려 있을 때만 무음 오디오로 앱을 깨워두며, 음악 재생은 방해하지 않습니다.")
                }
                .listRowBackground(Color.panel)
                Section {
                    LabeledContent("저장된 서버 키", value: "\(knownCount)개")
                    Button("서버 키 모두 초기화", role: .destructive) { confirmReset = true }
                } header: {
                    Text("보안")
                } footer: {
                    Text("서버를 재설치해서 키가 바뀐 경우 초기화하세요.")
                }
                .listRowBackground(Color.panel)
                Section("정보") {
                    LabeledContent("버전", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                    LabeledContent("터미널 엔진", value: "SwiftTerm")
                    LabeledContent("SSH 엔진", value: "Citadel (SwiftNIO SSH)")
                }
                .listRowBackground(Color.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
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
