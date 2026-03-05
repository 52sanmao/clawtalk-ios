import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    var settingsStore: SettingsStore
    @State private var showSettings = false
    @State private var textInput = ""
    @State private var showTextInput = true

    var body: some View {
        VStack(spacing: 0) {
            // Custom nav bar
            navBar
            Divider().opacity(0.3)

            // Chat area
            messageList

            // Input area
            Divider().opacity(0.3)
            inputArea
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showSettings) {
            SettingsView(store: settingsStore)
        }
    }

    // MARK: - Navigation Bar

    private var navBar: some View {
        HStack {
            // Balance the right button
            Image(systemName: "gearshape.fill")
                .font(.body)
                .hidden()

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.subheadline)
                    .foregroundStyle(.openClawRed)
                Text("ClawTalk")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Spacer()

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(.openClawRed)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if viewModel.messages.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.last?.content) {
                if let lastID = viewModel.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 0) {
            // Error banner
            if let error = viewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showTextInput {
                // Text mode: compact bar with text field + mic switch
                // State indicator inline
                if viewModel.state != .idle {
                    stateIndicator
                        .padding(.top, 10)
                        .transition(.opacity)
                }

                HStack(spacing: 10) {
                    TextField("Message...", text: $textInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Mic button to switch to voice mode
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showTextInput = false } }) {
                            Image(systemName: "mic.fill")
                                .font(.body)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.openClawRed)
                                .clipShape(Circle())
                        }
                    } else {
                        // Send button
                        Button(action: {
                            viewModel.sendText(textInput)
                            textInput = ""
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title)
                                .foregroundStyle(.openClawRed)
                        }
                        .disabled(viewModel.state != .idle)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            } else {
                // Voice mode: full-width area with push-to-talk
                VStack(spacing: 12) {
                    // State indicator
                    if viewModel.state != .idle {
                        stateIndicator
                            .padding(.top, 8)
                            .transition(.opacity)
                    }

                    TalkButton(
                        state: viewModel.state,
                        audioLevel: viewModel.audioLevel,
                        onPress: { viewModel.startRecording() },
                        onRelease: { viewModel.stopRecordingAndSend() }
                    )

                    // Keyboard button to switch to text mode
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showTextInput = true } }) {
                        Image(systemName: "keyboard")
                            .font(.title3)
                            .foregroundStyle(.openClawRed)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.secondarySystemBackground))
        .animation(.easeInOut(duration: 0.2), value: viewModel.state)
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage != nil)
    }

    // MARK: - State Indicator

    private var stateIndicator: some View {
        HStack(spacing: 8) {
            switch viewModel.state {
            case .recording:
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Listening...")
            case .transcribing:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Transcribing...")
            case .thinking:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Thinking...")
            case .streaming:
                Circle()
                    .fill(.openClawRed)
                    .frame(width: 8, height: 8)
                    .modifier(PulsingModifier())
                Text("Responding...")
            case .speaking:
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.openClawRed)
                    .symbolEffect(.variableColor.iterative)
                Text("Speaking...")
            case .idle:
                EmptyView()
            }
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(.systemGray5).opacity(0.8))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 100)

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.openClawRed.opacity(0.5))

            Text("ClawTalk")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text("Type a message, or tap the\nmic to use voice input.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct PulsingModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.4 : 1.0)
            .opacity(pulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
