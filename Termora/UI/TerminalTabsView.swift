//
//  TerminalTabsView.swift
//  Termora
//

import AppKit
import GhosttyTerminal
import SwiftUI
import TermoraModel

/// The terminal area: a tab bar, and the split tree of the chosen tab.
struct TerminalTabsView: View {
    @EnvironmentObject private var sessions: SessionsController

    // The tab row is not here: it lives in the window's title bar, as an
    // accessory. See the note on `TitlebarTabs` for the two designs that
    // were tried and failed.
    var body: some View {
        Group {
            if sessions.tabs.isEmpty {
                // The frame fills the column, so the bar above stays at the
                // top instead of centring with this view.
                ContentUnavailableView(
                    "No session",
                    systemImage: "terminal",
                    description: Text("Double-click a connection in the sidebar to open it, "
                        + "or press ⌘T for a shell on this Mac.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Every tab is drawn, and the ones you cannot see are made
                // clear. A tab must not be taken out of the view tree: that
                // ends its terminal surface, and libghostty cannot give the
                // same terminal a second surface. The tab would then stay
                // empty for ever, even after you come back to it.
                //
                // `updateVisibility` stops libghostty drawing the hidden ones,
                // so nothing is wasted.
                ZStack {
                    ForEach(sessions.tabs) { tab in
                        TabContent(tab: tab)
                            .opacity(tab.id == sessions.selectedTabID ? 1 : 0)
                            .allowsHitTesting(tab.id == sessions.selectedTabID)
                            .accessibilityHidden(tab.id != sessions.selectedTabID)
                    }
                }
            }
        }
        .onChange(of: sessions.selectedTabID) { _, _ in
            sessions.updateVisibility()
            if let pane = sessions.selectedTab?.panes
                .first(where: { $0.id == sessions.selectedTab?.focusedPaneID }) {
                pane.focus()
            } else {
                // A focused hidden surface would answer ⌘W for another tab.
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
}

/// The row of open tabs.
struct TabBar: View {
    @EnvironmentObject private var sessions: SessionsController

    /// The height of the row of tabs.
    ///
    /// A horizontal `ScrollView` takes whatever height it is offered. Inside a
    /// row it is offered none, and it then draws nothing at all, which is why
    /// the height is named here on both the content and the scroll view.
    static let height: CGFloat = 28

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(sessions.tabs.enumerated()), id: \.element.id) { at, tab in
                    TabButton(
                        tab: tab,
                        position: at,
                        isSelected: tab.id == sessions.selectedTabID
                    )
                }
            }
            .padding(.horizontal, 4)
            .frame(height: Self.height)
        }
        .frame(height: Self.height)
    }
}

private struct TabButton: View {
    @ObservedObject var tab: TerminalTab
    /// Where the tab sits in the row, counted from zero.
    let position: Int
    let isSelected: Bool
    @EnvironmentObject private var sessions: SessionsController
    @State private var isHovering = false
    @State private var isHoveringClose = false

    var body: some View {
        HStack(spacing: 5) {
            // A local tab has no connection, so it has no status to show.
            // The empty dot keeps its icon in line with the other tabs.
            Circle()
                .fill(tab.isLocal ? .clear : statusColor)
                .frame(width: 6, height: 6)
            // The colour tag tints the icon, the way the sidebar does. It
            // must not touch the status dot: a red Production tag and a red
            // "failed" dot would then look the same.
            Image(systemName: tab.iconName)
                .font(.system(size: 10))
                .foregroundStyle(tagTint)
            TabTitle(tab: tab)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            // The name takes the room that is left, so the slot after it sits
            // in the corner of the tab and not beside the name.
            Spacer(minLength: 2)
            // One slot at the end of the tab, of one size. It holds the key
            // that chooses the tab, and the close mark while the pointer is
            // over the tab. The name never moves as the two change over.
            ZStack {
                if isHovering {
                    closeMark
                } else if let shortcut = shortcutName {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 20, height: 13)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        // Every tab is the same size, so the gaps between them are even and
        // a long name cannot push its neighbours about.
        .frame(width: 150, height: TabBar.height - 6)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isSelected ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.clear))
        )
        .overlay { attentionGlow }
        .contentShape(Rectangle())
        .onTapGesture { sessions.selectedTabID = tab.id }
        .onHover { isHovering = $0 }
        .help(tab.isLocal ? (tab.focusedPane?.workingDirectory ?? tab.name) : tab.name)
        .contextMenu { menu }
        // A name a test can ask for. Without it, a test looking for the tab
        // finds the sidebar row of the same name and passes while the tab bar
        // draws nothing at all.
        .accessibilityIdentifier("tab-\(tab.name)")
        // The chosen tab says so, for VoiceOver and for the tests.
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityValue(attentionDescription ?? "")
    }

    /// A coloured edge with a soft glow, on a hidden tab whose pane rang the
    /// bell or ended a long command. It is drawn after the clip, so the glow
    /// can reach past the edge of the tab.
    @ViewBuilder
    private var attentionGlow: some View {
        if let color = attentionColor {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(color, lineWidth: 1.5)
                .shadow(color: color.opacity(0.8), radius: 3)
                .allowsHitTesting(false)
        }
    }

    private var attentionColor: Color? {
        switch tab.attention {
        case nil: nil
        case .neutral: .accentColor
        case .success: .green
        case .failure: .red
        }
    }

    private var attentionDescription: String? {
        switch tab.attention {
        case nil: nil
        case .neutral: "Needs attention"
        case .success: "Command finished"
        case .failure: "Command failed"
        }
    }

    private var closeMark: some View {
        Button {
            sessions.closeTab(tab.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 13, height: 13)
                .background(
                    Circle().fill(isHoveringClose
                                  ? AnyShapeStyle(.tertiary)
                                  : AnyShapeStyle(.clear))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringClose = $0 }
        .help("Close this tab")
    }

    /// The key that chooses this tab, or nothing after the ninth tab.
    ///
    /// The menu binds ⌘1…⌘9 to the first nine tabs. See the Session menu in
    /// `TermoraApp`.
    private var shortcutName: String? {
        guard position < 9 else { return nil }
        return "⌘\(position + 1)"
    }

    /// A tab you point at is marked, so it is clear what a click will hit.
    ///
    /// The chosen tab is drawn solid. `.selection` is not used: on a bar it
    /// is nearly the colour of the bar itself, and the chosen tab then looks
    /// the same as every other one.
    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.background) }
        if isHovering { return AnyShapeStyle(.tertiary) }
        // Every tab carries a light ground, so the row reads as a row of
        // tabs. With nothing behind them the names float on the bar and the
        // space between them looks uneven.
        return AnyShapeStyle(.quaternary)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Browse Files") { sessions.openFiles(for: tab) }
            .disabled(sessions.connection(of: tab) == nil)
        Button("Duplicate") { sessions.duplicate(tab) }
            .disabled(!sessions.canDuplicate(tab))
        if sessions.isQuick(tab) {
            Button("Save as Bookmark") { sessions.saveAsBookmark(tab) }
        }
        Divider()
        Button("Close") { sessions.closeTab(tab.id) }
        Button("Close Other Tabs") { sessions.closeOtherTabs(than: tab.id) }
            .disabled(sessions.tabs.count < 2)
    }

    /// The dot says status and nothing else: orange, green, or red.
    private var statusColor: Color {
        if tab.isReconnecting { return .orange }
        if tab.lostReason != nil { return .red }
        return switch tab.phase {
        case .connecting, .running: .orange
        case .ready: .green
        case .failed: .red
        }
    }

    private var tagTint: Color {
        switch tab.colorTag {
        case .none: .secondary
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .grey: .gray
        }
    }
}

/// The name on a tab.
///
/// A local tab follows the folder of its focused shell. The view watches
/// that pane, because the tab itself does not publish a change of folder.
private struct TabTitle: View {
    @ObservedObject var tab: TerminalTab

    var body: some View {
        if tab.isLocal, let pane = tab.focusedPane {
            LocalFolderName(state: pane.state, fallback: tab.name)
        } else {
            Text(tab.name)
        }
    }
}

private struct LocalFolderName: View {
    @ObservedObject var state: TerminalViewState
    let fallback: String

    var body: some View {
        Text(TerminalTab.folderName(state.workingDirectory) ?? fallback)
    }
}

private struct TabContent: View {
    @ObservedObject var tab: TerminalTab
    @EnvironmentObject private var sessions: SessionsController

    var body: some View {
        switch tab.phase {
        case let .running(name):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Running \(name)…")
                    Spacer()
                }
                Text("This command runs on this Mac, before the connection opens.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                CommandLog(text: tab.commandLog)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .connecting:
            VStack(spacing: 12) {
                ProgressView()
                Text("Connecting to \(tab.name)…")
                    .foregroundStyle(.secondary)
                Text("Answer any question that appears.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                // A host that does not answer holds the tab until the TCP
                // timeout. This is the way out.
                Button("Cancel") { sessions.closeTab(tab.id) }
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(reason):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text("Shellyard could not connect to \(tab.name).")
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                HStack {
                    Button("Close Tab") { sessions.closeTab(tab.id) }
                    Button("Try Again") { sessions.reconnect(tab) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!sessions.canReconnect(tab))
                }
                if !tab.commandLog.isEmpty {
                    CommandLog(text: tab.commandLog)
                        .frame(maxWidth: 640)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

        case .ready:
            // The bar is an overlay, so a lost connection never changes the
            // view tree: the panes stay, with their last output.
            Group {
                if tab.kind == .files {
                    if let browser = tab.browser {
                        // A reconnect brings a new model. The identity makes
                        // the view load it, as its `.task` runs once per view.
                        FileBrowserView(model: browser)
                            .id(ObjectIdentifier(browser))
                    }
                } else if let root = tab.root {
                    PaneTreeView(node: root, tab: tab)
                }
            }
            .overlay(alignment: .top) {
                if let reason = tab.lostReason {
                    LostConnectionBar(tab: tab, reason: reason)
                }
            }
        }
    }
}

/// The bar over a tab whose connection stopped by itself.
private struct LostConnectionBar: View {
    @ObservedObject var tab: TerminalTab
    let reason: String
    @EnvironmentObject private var sessions: SessionsController

    var body: some View {
        HStack(spacing: 10) {
            if tab.isReconnecting {
                ProgressView().controlSize(.small)
                Text("Reconnecting to \(tab.name)…")
                Spacer()
            } else {
                Image(systemName: "bolt.horizontal.circle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("The connection to \(tab.name) closed.")
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Close Tab") { sessions.closeTab(tab.id) }
                Button("Reconnect") { sessions.reconnect(tab) }
                    .buttonStyle(.borderedProminent)
                    .help("Reconnect (⌘R)")
                    .accessibilityIdentifier("reconnect-button")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .padding(10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lost-connection-bar")
    }
}

/// Draws a node: either one pane, or two nodes with a divider between them.
private struct PaneTreeView: View {
    @ObservedObject var node: PaneNode
    @ObservedObject var tab: TerminalTab

    var body: some View {
        switch node.content {
        case let .pane(session):
            // A reconnect puts a new session in the same node. The identity
            // makes a new surface view for it: a surface view cannot take a
            // second session.
            TerminalPaneView(session: session, tab: tab)
                .id(session.id)
        case let .split(axis, first, second):
            SplitContainer(axis: axis, ratio: $node.ratio) {
                PaneTreeView(node: first, tab: tab)
            } second: {
                PaneTreeView(node: second, tab: tab)
            }
        }
    }
}

/// One terminal surface, with a mark showing which pane has the keyboard.
private struct TerminalPaneView: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var tab: TerminalTab
    @EnvironmentObject private var sessions: SessionsController

    private var isFocused: Bool { tab.focusedPaneID == session.id }

    var body: some View {
        TerminalSurfaceView(context: session.state)
            .overlay(alignment: .top) {
                // A thin line, so a split shows which half takes the keys
                // without a border that eats space.
                Rectangle()
                    .fill(.tint)
                    .frame(height: 2)
                    .opacity(isFocused && tab.panes.count > 1 ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { sessions.focus(paneID: session.id, in: tab) }
            .onAppear {
                // Only a pane on the chosen tab may take the keyboard. A
                // session that becomes ready behind another tab appears too,
                // and it must not steal the keys from what you are typing in.
                if isFocused, sessions.selectedTabID == tab.id { session.focus() }
            }
    }
}

/// Two views with a divider you can drag.
///
/// This is used for the terminal splits and for the two panes of the file
/// browser. `HSplitView` is not: its split view takes the whole window
/// height once the safe area above it is ignored, and it then draws over
/// the tab bar.
struct SplitContainer<First: View, Second: View>: View {
    let axis: Axis
    @Binding var ratio: Double
    @ViewBuilder let first: First
    @ViewBuilder let second: Second

    private let thickness: CGFloat = 6
    /// Neither side may shrink past this share, so a pane never disappears.
    private let limits = 0.1 ... 0.9
    /// The ratio when the drag began. A drag reports the distance from its own
    /// start, so without this the movement would add up on every change.
    @State private var ratioAtDragStart: Double?

    var body: some View {
        GeometryReader { geometry in
            let total = axis == .horizontal ? geometry.size.width : geometry.size.height
            let usable = max(total - thickness, 1)
            let firstLength = usable * ratio

            if axis == .horizontal {
                HStack(spacing: 0) {
                    first.frame(width: firstLength)
                    divider(total: usable)
                    second.frame(width: max(usable - firstLength, 0))
                }
            } else {
                VStack(spacing: 0) {
                    first.frame(height: firstLength)
                    divider(total: usable)
                    second.frame(height: max(usable - firstLength, 0))
                }
            }
        }
    }

    private func divider(total: CGFloat) -> some View {
        Rectangle()
            .fill(.separator)
            .frame(
                width: axis == .horizontal ? thickness : nil,
                height: axis == .horizontal ? nil : thickness
            )
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    axis == .horizontal
                        ? NSCursor.resizeLeftRight.push()
                        : NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = ratioAtDragStart ?? ratio
                        if ratioAtDragStart == nil { ratioAtDragStart = ratio }
                        let delta = axis == .horizontal
                            ? value.translation.width
                            : value.translation.height
                        let proposed = start + delta / total
                        ratio = min(max(proposed, limits.lowerBound), limits.upperBound)
                    }
                    .onEnded { _ in ratioAtDragStart = nil }
            )
    }
}


/// Shows what a command printed, and keeps the newest line in sight.
private struct CommandLog: View {
    let text: String

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                Text(text.isEmpty ? "No output yet." : text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .id("end")
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxHeight: 320)
            .onChange(of: text) { _, _ in
                scroller.scrollTo("end", anchor: .bottom)
            }
        }
    }
}
