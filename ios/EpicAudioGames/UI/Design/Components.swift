// ui/Components.kt: the app's building blocks on the theme's tokens: headings, buttons, settings rows and status text.

import SwiftUI

// Everything that can be touched is at least 48 pt, and says in words what its colour shows. iOS draws the keyboard's
// focus ring itself (Full Keyboard Access, in the colour the player picks there), so there's no focusRing here as
// Android has; a pointer (an iPad's trackpad or mouse, a Mac) gets each button's hover effect.
//
// What a button does is a main-actor function (@MainActor () -> Void), as SwiftUI's Button takes it: a plain
// function value would be converted to one at each Button, which Swift 6 warns may race.

/// The widest the content gets on a big screen, so lines stay a readable length (Android's MAX_CONTENT_WIDTH).
let maxContentWidth: CGFloat = 640

extension View {
    /// As wide as there's room for, up to [maxContentWidth], centred on a wider screen; its content [alignment]ed in
    /// that width. Android's Modifier.readableWidth().
    func readableWidth(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: maxContentWidth, alignment: alignment)
            .frame(maxWidth: .infinity)
    }

    /**
     * VoiceOver moves to this a moment ([delay]: A11y.focusDelay) after it appears, and again for a new [key]: the end
     * panel's and the pause's headings (docs/DESIGN.md › Everywhere › Focus). By then the pane has been laid out, and
     * VoiceOver has said what changed. On a page just pushed or a sheet just risen (Licences, the store sheet), give
     * A11y.focusAfterTransition: iOS moves VoiceOver into the new screen itself as the transition ends, which would
     * take it from a heading focused sooner. Put it on one element (a heading). Android's Modifier.focusOnAppear.
     */
    func focusOnAppear<Key: Equatable>(_ key: Key, after delay: Duration = A11y.focusDelay) -> some View {
        modifier(FocusOnAppear(key: key, delay: delay))
    }

    /**
     * VoiceOver moves to this a moment ([delay]: A11y.focusDelay, or A11y.focusAfterTransition on a page just pushed or
     * a sheet just risen) after [request] is made (not nil), and again for a new one; [then] is told once it has, so
     * the screen can let the request go: coming back into sight (a tab picked again) it doesn't move VoiceOver a second
     * time, as a tab picked keeps the focus on the tab (docs/DESIGN.md › Everywhere › Focus). For the Games heading
     * after the intro or onboarding, and a Help topic's heading as it opens. Android's focus requests asked for once
     * (focusGames, focusHelpTopic).
     */
    func focusWhen<Request: Equatable>(
        _ request: Request?, after delay: Duration = A11y.focusDelay, then: @escaping @MainActor () -> Void = {}
    ) -> some View {
        modifier(FocusWhen(request: request, delay: delay, then: then))
    }
}

private struct FocusOnAppear<Key: Equatable>: ViewModifier {
    let key: Key
    let delay: Duration
    @AccessibilityFocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($focused)
            // On the main actor, which the focus belongs to: said outright, whatever task infers.
            .task(id: key) { @MainActor in
                do { try await Task.sleep(for: delay) } catch { return }
                focused = true
            }
    }
}

private struct FocusWhen<Request: Equatable>: ViewModifier {
    let request: Request?
    let delay: Duration
    let then: @MainActor () -> Void
    @AccessibilityFocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($focused)
            // Gone from sight before the moment is up (the task cancelled), the request stays for when it's back.
            .task(id: request) { @MainActor in
                guard request != nil else { return }
                do { try await Task.sleep(for: delay) } catch { return }
                focused = true
                then()
            }
    }
}

/// A screen's title: the level-1 heading ("Games", "Shop").
struct ScreenHeader: View {
    let text: String
    @Environment(\.epicColors) private var c

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .epicFont(.title)
            .foregroundStyle(c.heading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHeading(.h1)
    }
}

/// A section's title: a level-2 heading (a game in the Shop, a group of settings, the store sheet's title).
struct SectionHeading: View {
    let text: String
    @Environment(\.epicColors) private var c

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .epicFont(.headline)
            .foregroundStyle(c.heading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHeading(.h2)
    }
}

/// What a button is for: the one thing to do (filled), another choice (outlined), or a quiet one (words only).
enum ButtonKind {
    case primary, secondary, text
}

/**
 * A button: its words (sentence case, wrapping onto more lines rather than cut short), after an [icon] if it has one;
 * at least 48 pt tall, and [wide] as wide as there's room for. [description] is what VoiceOver says when it needs more
 * than the words, and it starts with them ("Buy for £1.99: The Werewolf, 45 more mysteries"); Voice Control still
 * knows the button by what it shows. [busy] shows a spinner in the icon's place; the button still works. Disabled, its
 * words stay at full strength (text never fades): it loses its fill and is outlined instead. With Button Shapes on, a
 * button that's only words is underlined. Android's EpicButton.
 */
struct EpicButton: View {
    let text: String
    var kind: ButtonKind
    var icon: MaterialIcon?
    var enabled: Bool
    var description: String?
    var busy: Bool
    var wide: Bool
    let action: @MainActor () -> Void
    @Environment(\.epicColors) private var c
    @Environment(\.epicButtonShapes) private var buttonShapes

    init(
        _ text: String, kind: ButtonKind = .primary, icon: MaterialIcon? = nil, enabled: Bool = true,
        description: String? = nil, busy: Bool = false, wide: Bool = false, action: @escaping @MainActor () -> Void
    ) {
        self.text = text
        self.kind = kind
        self.icon = icon
        self.enabled = enabled
        self.description = description
        self.busy = busy
        self.wide = wide
        self.action = action
    }

    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        let content = contentColor
        let filled = kind == .primary && enabled
        let outlined = kind == .secondary || (kind == .primary && !enabled)
        Button(action: action) {
            HStack(spacing: busy ? 10 : 8) {
                if busy {
                    ProgressView()
                        .tint(content)
                        .accessibilityHidden(true)
                } else if let icon {
                    IconView(icon: icon, size: 24, color: content)
                }
                // Centred on each line, when it wraps (large text).
                Text(text)
                    .underline(kind == .text && buttonShapes)
                    .epicFont(.label)
                    .foregroundStyle(content)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: wide ? CGFloat.infinity : nil, minHeight: 48)
            .background {
                if filled { Self.shape.fill(c.primary) }
            }
            .overlay {
                if outlined { Self.shape.strokeBorder(c.outline, lineWidth: 2) }
            }
            .contentShape(Self.shape)
        }
        .buttonStyle(PressStyle())
        .hoverEffect()
        .disabled(!enabled)
        .accessibilityLabel(description ?? text)
        .accessibilityInputLabels(A11y.inputLabels(text))
    }

    private var contentColor: Color {
        if !enabled { return c.textMuted }
        switch kind {
        case .primary: return c.onPrimary
        case .secondary: return c.text
        case .text: return c.heading
        }
    }
}

/// A button that's only an icon (Back, ⋮, Send): 48 pt, named by [description].
struct IconActionButton: View {
    let icon: MaterialIcon
    let description: String
    var enabled = true
    /// The icon's colour, the text's unless it says.
    var tint: Color?
    let action: @MainActor () -> Void
    @Environment(\.epicColors) private var c

    var body: some View {
        Button(action: action) {
            IconView(icon: icon, size: 24, color: enabled ? tint ?? c.text : c.textMuted)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(RippleStyle(shape: Circle()))
        .hoverEffect()
        .disabled(!enabled)
        .accessibilityLabel(description)
    }
}

/**
 * A setting that's on or off: its title (and a [hint] under it), and the switch. The whole row is the switch, as
 * Android's toggleable row is: VoiceOver finds it as one element the row's size ("Listening sounds, switch button,
 * on"; the hint after it), and every word shown is inside it. A tap on the words flips it too. Disabled, it says why
 * in the hint ("On in your phone's settings"), its words in the muted colour rather than faded. [identifier] is the
 * switch's (the one element: "setting-introSound"). Android's SwitchRow.
 */
struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    var hint: String?
    var enabled = true
    var identifier: String?
    @Environment(\.epicColors) private var c

    var body: some View {
        // The words are the switch's label, so its element (and its frame) is the whole row, not the switch alone.
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .epicFont(.body)
                    .foregroundStyle(enabled ? c.text : c.textMuted)
                if let hint {
                    Text(hint)
                        .epicFont(.secondary)
                        .foregroundStyle(c.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // iOS's switch takes a tap on itself only.
            .contentShape(Rectangle())
            .onTapGesture { if enabled { isOn.toggle() } }
        }
        .tint(c.primary)
        .disabled(!enabled)
        // Named by its title alone, the hint read after it.
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
        .accessibilityIdentifier(identifier ?? "")
        .padding(.vertical, 8)
        .frame(minHeight: 48)
    }
}

/**
 * One of a few choices (a theme, a text size): a whole row each, its mark filled when it's the one, in a group
 * VoiceOver moves through ("Dark, selected, button"). [hint] adds a line under a choice, [decoration] a picture after
 * its words (a theme's swatch: VoiceOver doesn't read it), and [tag] its test identifier ("setting-theme-dark").
 * Android's ChoiceGroup (radio buttons).
 */
struct ChoiceGroup<T: Hashable, Decoration: View>: View {
    let choices: [T]
    let selected: T
    let onSelect: (T) -> Void
    let label: (T) -> String
    var hint: (T) -> String? = { _ in nil }
    var enabled = true
    var tag: (T) -> String? = { _ in nil }
    @ViewBuilder var decoration: (T) -> Decoration
    @Environment(\.epicColors) private var c

    var body: some View {
        VStack(spacing: 0) {
            ForEach(choices, id: \.self) { choice in
                let on = choice == selected
                let mark = enabled ? (on ? c.primary : c.outline) : c.textMuted
                Button {
                    onSelect(choice)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().strokeBorder(mark, lineWidth: 2)
                            if on { Circle().fill(mark).padding(6) }
                        }
                        .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(choice))
                                .epicFont(.body)
                                .foregroundStyle(enabled ? c.text : c.textMuted)
                            if let more = hint(choice) {
                                Text(more)
                                    .epicFont(.secondary)
                                    .foregroundStyle(c.textMuted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        decoration(choice)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 6)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .hoverEffect()
                .disabled(!enabled)
                .accessibilityAddTraits(on ? .isSelected : [])
                // Voice Control knows it by its words alone ("Tap Longer"): VoiceOver reads its hint after them.
                .accessibilityInputLabels(A11y.inputLabels(label(choice)))
                .accessibilityIdentifier(tag(choice) ?? "")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension ChoiceGroup where Decoration == EmptyView {
    /// Choices with only their words (and hints).
    init(
        choices: [T], selected: T, onSelect: @escaping (T) -> Void, label: @escaping (T) -> String,
        hint: @escaping (T) -> String? = { _ in nil }, enabled: Bool = true, tag: @escaping (T) -> String? = { _ in nil }
    ) {
        self.init(
            choices: choices, selected: selected, onSelect: onSelect, label: label, hint: hint, enabled: enabled,
            tag: tag, decoration: { _ in EmptyView() })
    }
}

/**
 * A value moved a step at a time (the voice speed): Slower, the value in words, Faster. Each button stops at its end.
 * VoiceOver hears the new value after a tap (Android's is a polite live region). While the longest value fits between
 * the buttons on one line they share a row; with less room (large text) the value has a line of its own and the
 * buttons share the row under it, or at the largest sizes take a row each, so no word is ever broken. Android's
 * SpeedStepper.
 */
struct SpeedStepper: View {
    let value: Double
    let steps: [Double]
    let onChange: (Double) -> Void
    var describe: (Double) -> String = speedWords
    @Environment(\.epicColors) private var c

    var body: some View {
        // The first layout that fits the width, each judged by its words on one line.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                slower(wide: false)
                words
                faster(wide: false)
            }
            VStack(spacing: 8) {
                words
                HStack(spacing: 12) {
                    slower(wide: true)
                    faster(wide: true)
                }
            }
            VStack(spacing: 8) {
                words
                slower(wide: true)
                faster(wide: true)
            }
        }
        // Settings has no microphone open.
        .onChange(of: value) { _, now in A11y.announce(describe(now), unlessListening: false) }
    }

    /// Where [value] is among the steps (the first, if it's none of them).
    private var index: Int { steps.firstIndex { abs($0 - value) < 0.001 } ?? 0 }

    private func slower(wide: Bool) -> some View {
        let i = index
        return EpicButton("Slower", kind: .secondary, enabled: i > 0, wide: wide) { onChange(steps[i - 1]) }
    }

    private func faster(wide: Bool) -> some View {
        let i = index
        return EpicButton("Faster", kind: .secondary, enabled: i < steps.count - 1, wide: wide) {
            onChange(steps[i + 1])
        }
    }

    /// The value in words, as wide as the longest of them, so the layout doesn't change as the value does.
    private var words: some View {
        let longest = steps.map(describe).max { $0.count < $1.count } ?? ""
        return ZStack {
            Text(longest)
                .epicFont(.label)
                .hidden()
                .accessibilityHidden(true)
            Text(describe(value))
                .epicFont(.label)
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A voice speed in words: "Normal speed", "1.25 times" (Android's speedWords).
nonisolated func speedWords(_ speed: Double) -> String {
    if abs(speed - 1) < 0.001 { return "Normal speed" }
    let number = String(speed)
    return (number.hasSuffix(".0") ? String(number.dropLast(2)) : number) + " times"
}

/// What a status message is about: its colour, always with an icon and words too.
enum StatusKind {
    case info, success, error
}

/**
 * A status message (a purchase done, a download failed, restored), as one element VoiceOver reads as its words. It
 * isn't announced by itself: the screen that shows it does that (A11y.announce), as only it knows the mic isn't
 * listening. Android's StatusText, a polite live region there.
 */
struct StatusText: View {
    let text: String
    var kind: StatusKind = .info
    @Environment(\.epicColors) private var c

    var body: some View {
        let color = kind == .success ? c.success : kind == .error ? c.error : c.text
        HStack(alignment: .top, spacing: 8) {
            switch kind {
            case .info:
                EmptyView()
            case .success:
                IconView(icon: .checkCircle, size: 24, color: color).padding(.top, 1)
            case .error:
                IconView(icon: .errorOutline, size: 24, color: color).padding(.top, 1)
            }
            Text(text)
                .epicFont(.body)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// A web page to open in the browser (the privacy policy): underlined, as links always are, with an "opens" icon.
struct LinkRow: View {
    let text: String
    let action: @MainActor () -> Void
    @Environment(\.epicColors) private var c

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text)
                    .underline()
                    .epicFont(.body)
                    .foregroundStyle(c.heading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                IconView(icon: .openInNew, size: 24, color: c.heading)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .hoverEffect()
        .accessibilityRemoveTraits(.isButton)
        .accessibilityAddTraits(.isLink)
    }
}

/**
 * A page of the app to go to (Settings › Licences, How to play): a whole-row button, its words in the body style and a
 * chevron, so it doesn't look like a web link (those are underlined, LinkRow). Android's PageRow.
 */
struct PageRow: View {
    let text: String
    let action: @MainActor () -> Void
    @Environment(\.epicColors) private var c

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text)
                    .epicFont(.body)
                    .foregroundStyle(c.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                IconView(icon: .keyboardArrowRight, size: 24, color: c.text)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .hoverEffect()
    }
}

/**
 * A keyboard's shortcut with no button to see (docs/DESIGN.md › Tablets… › Keyboard): Space and Escape in a game, ⌘1 to
 * ⌘4 for the tabs, Escape on a page. iPadOS lists it by [title] while ⌘ is held; VoiceOver doesn't find it, as it has
 * the buttons themselves (and Magic Tap, and its own escape). Only while [enabled]: off, the key goes its usual way.
 * Android's KeyShortcuts (Keyboard.kt).
 */
struct ShortcutKey: View {
    let title: String
    let key: KeyEquivalent
    var modifiers: EventModifiers = []
    var enabled = true
    let action: @MainActor () -> Void

    var body: some View {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(!enabled)
            // Nothing to see or touch, but there: a hidden button's shortcut doesn't work.
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}

/// A small label with an icon ("In progress"): words, so it isn't colour alone.
struct Badge: View {
    let text: String
    var icon: MaterialIcon?
    @Environment(\.epicColors) private var c

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                IconView(icon: icon, size: 20, color: c.onPrimary)
            }
            Text(text)
                .epicFont(.speaker)
                .foregroundStyle(c.onPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(c.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
