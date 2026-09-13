import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 7) {
                Text(NFSLocalized.text("选择索引位置", "Choose an indexed location"))
                    .font(.title2.weight(.semibold))
                Text(NFSLocalized.text(
                    "首次使用时不会自动访问桌面、文稿或其他文件夹。请手动选择一个希望搜索的目录。",
                    "NativeFileSearch will not access Desktop, Documents, or other folders automatically. Choose a folder you want to search."
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(NFSLocalized.text(
                "只有在你确认选择后，应用才会请求该目录的访问权限并建立本地索引。以后可以在设置中继续添加或删除位置。",
                "The app requests access and builds a local index only after you confirm a folder. You can add or remove locations later in Settings."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(NFSLocalized.text("稍后设置", "Set up later")) {
                    appState.completeInitialSetup()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(NFSLocalized.text("选择文件夹", "Choose Folder")) {
                    appState.completeInitialSetup()
                    appState.chooseFolder()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 520, height: 330)
    }
}
