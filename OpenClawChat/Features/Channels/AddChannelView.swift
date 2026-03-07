import SwiftUI

struct AddChannelView: View {
    var channelStore: ChannelStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var agentId = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Channel Name", text: $name)
                    TextField("Agent ID", text: $agentId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Configuration")
                } footer: {
                    Text("The Agent ID identifies which OpenClaw agent to route to. Use \"main\" for the default agent.")
                }
            }
            .navigationTitle("New Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let channel = Channel(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            agentId: agentId.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        channelStore.add(channel)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              agentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
