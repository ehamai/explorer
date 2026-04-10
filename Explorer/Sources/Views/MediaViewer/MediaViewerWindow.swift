import SwiftUI
import AVKit

struct MediaViewerWindow: View {
    @State private var viewModel: MediaViewerViewModel
    @State private var showDeleteConfirmation = false
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(context: MediaViewerContext) {
        _viewModel = State(initialValue: MediaViewerViewModel(context: context))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                    Text(error)
                        .foregroundStyle(.white)
                        .font(.headline)
                }
            } else if viewModel.mediaType == .image, let image = viewModel.displayImage {
                ImageViewerView(image: image)
            } else if viewModel.mediaType == .video, let player = viewModel.player {
                VideoViewerView(player: player, loopEnabled: Binding(
                    get: { viewModel.loopVideo },
                    set: { viewModel.loopVideo = $0 }
                ))
            }

            if showDeleteConfirmation {
                DeleteConfirmationOverlay(
                    fileName: viewModel.windowTitle,
                    onConfirm: {
                        showDeleteConfirmation = false
                        viewModel.trashCurrentFile()
                        restoreFocus()
                    },
                    onCancel: {
                        showDeleteConfirmation = false
                        restoreFocus()
                    }
                )
            }
        }
        .focusable(!showDeleteConfirmation)
        .focused($isFocused)
        .focusEffectDisabled()
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle(viewModel.windowTitle)
        .onAppear {
            viewModel.loadMedia()
            viewModel.startListeningForDeletions()
            isFocused = true
        }
        .onDisappear { viewModel.cleanup() }
        .onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .onChange(of: viewModel.currentURL) { _, _ in
            restoreFocus()
        }
        .onKeyPress(.leftArrow) {
            guard !showDeleteConfirmation else { return .ignored }
            viewModel.goToPrevious()
            restoreFocus()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !showDeleteConfirmation else { return .ignored }
            viewModel.goToNext()
            restoreFocus()
            return .handled
        }
        .onKeyPress(.escape) {
            guard !showDeleteConfirmation else { return .ignored }
            dismiss()
            return .handled
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: {
                    viewModel.goToPrevious()
                    restoreFocus()
                }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!viewModel.canGoPrevious)
                .help("Previous (←)")

                Text(viewModel.statusText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 50)

                Button(action: {
                    viewModel.goToNext()
                    restoreFocus()
                }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!viewModel.canGoNext)
                .help("Next (→)")

                Divider()

                Button(action: { viewModel.loopVideo.toggle() }) {
                    Image(systemName: viewModel.loopVideo ? "repeat.circle.fill" : "repeat.circle")
                        .foregroundStyle(viewModel.loopVideo ? Color.accentColor : Color.secondary)
                }
                .help(viewModel.loopVideo ? "Looping On (⌘L)" : "Looping Off (⌘L)")
                .keyboardShortcut("l", modifiers: .command)

                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                }
                .keyboardShortcut("d", modifiers: .command)
                .help("Move to Trash (⌘D)")
            }
        }
    }

    /// Restore focus to the media viewer after the dialog closes.
    /// Delayed slightly to allow SwiftUI to tear down the dialog's focusable view first.
    private func restoreFocus() {
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            isFocused = true
        }
    }
}

// MARK: - Delete Confirmation Overlay

/// Custom modal dialog with full keyboard support: Tab switches between buttons,
/// Enter confirms the selected button, Escape cancels.
private struct DeleteConfirmationOverlay: View {
    let fileName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var selectedButton: SelectedButton = .cancel
    @FocusState private var dialogFocused: Bool

    enum SelectedButton { case trash, cancel }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.red)

                    Text("Move to Trash")
                        .font(.headline)

                    Text("Are you sure you want to move \"\(fileName)\" to the Trash?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                Divider()

                HStack(spacing: 12) {
                    dialogButton(
                        label: "Cancel",
                        isSelected: selectedButton == .cancel,
                        isDestructive: false,
                        action: onCancel
                    )

                    dialogButton(
                        label: "Move to Trash",
                        isSelected: selectedButton == .trash,
                        isDestructive: true,
                        action: onConfirm
                    )
                }
                .padding(16)
            }
            .frame(width: 360)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .focusable()
        .focused($dialogFocused)
        .focusEffectDisabled()
        .onAppear { dialogFocused = true }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
        .onKeyPress(.tab) {
            selectedButton = (selectedButton == .trash) ? .cancel : .trash
            return .handled
        }
        .onKeyPress(.return) {
            if selectedButton == .trash {
                onConfirm()
            } else {
                onCancel()
            }
            return .handled
        }
    }

    @ViewBuilder
    private func dialogButton(label: String, isSelected: Bool, isDestructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isDestructive && isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected
                              ? (isDestructive ? Color.red : Color.accentColor)
                              : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected
                                      ? (isDestructive ? Color.red : Color.accentColor)
                                      : Color(nsColor: .separatorColor),
                                      lineWidth: isSelected ? 2 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
