import SwiftUI

struct AddChannelView: View {
    var channelStore: ChannelStore
    var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var agentId = ""
    @State private var agents: [AgentEntry] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let client = OpenClawClient()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Channel Name", text: $name)
                } header: {
                    Text("Name")
                }

                Section {
                    if isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading agents…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if !agents.isEmpty {
                        ForEach(agents) { agent in
                            Button(action: {
                                agentId = agent.agentId
                                if name.isEmpty {
                                    name = agent.agentId.capitalized
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(agent.agentId)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        if agent.configured == true {
                                            Text("Configured")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if agentId == agent.agentId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.openClawRed)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        // Fallback to manual text field
                        TextField("Agent ID (e.g. main)", text: $agentId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    if let error = loadError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Agent")
                } footer: {
                    if agents.isEmpty && !isLoading {
                        Text("Enter the Agent ID to route to. Use \"main\" for the default agent.")
                    }
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
            .task {
                await loadAgents()
            }
        }
    }

    private func loadAgents() async {
        guard settings.isConfigured else {
            loadError = "Configure your gateway in Settings first."
            return
        }

        isLoading = true
        do {
            let data = try await client.invokeTool(
                tool: "agents_list",
                gatewayURL: settings.settings.gatewayURL,
                token: settings.gatewayToken
            )
            let wrapper = try JSONDecoder().decode(ToolResultWrapper<AgentsListResult>.self, from: data)
            agents = wrapper.details?.agents ?? []
        } catch {
            loadError = "Could not load agents."
        }
        isLoading = false
    }
}
