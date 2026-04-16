import SwiftUI

/// A banner that slides in from the top when exec approvals are pending.
/// Mobile clients currently show this as a read-only notice.
struct ApprovalBannerView: View {
    var approval: PendingApproval
    var onResolve: (String, String) -> Void  // (id, decision)

    @State private var showFullCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.yellow)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("执行审批请求")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let agent = approval.agentId {
                        Text("代理: \(agent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Countdown
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let remaining = max(0, approval.expiresAt.timeIntervalSinceNow)
                    Text("\(Int(remaining))s")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(remaining < 30 ? .red : .secondary)
                        .monospacedDigit()
                }
            }

            // Custom question if provided
            if let ask = approval.ask {
                Text(ask)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            // Command
            Button(action: { showFullCommand.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(approval.displayCommand)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(showFullCommand ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Working directory
            if let cwd = approval.cwd {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.caption2)
                    Text(cwd)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            Text("IronClaw 当前未提供稳定的移动端审批提交接口，请在服务端完成审批。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label("请在服务端处理", systemImage: "hand.raised.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .foregroundStyle(.secondary)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .padding(.horizontal)
    }
}
