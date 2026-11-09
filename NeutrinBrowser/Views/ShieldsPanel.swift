import SwiftUI

/// Per-site Shields: on/off switch and what was blocked on this page.
struct ShieldsPanel: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: TabController
    @State private var showSettings = false

    private var host: String { controller.url?.displayHost ?? "" }
    private var isUp: Bool { store.shieldsEnabled(for: controller.url?.host) && store.shieldsAreConfigured }
    private var ads: [BlockedItem] { controller.blockedItems.filter { $0.category == .ads } }
    private var trackers: [BlockedItem] { controller.blockedItems.filter { $0.category == .trackers } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    counters
                    blockedList
                    protections
                }
                .padding(20)
            }
            .background(AppBackground())
            .navigationTitle("Shields")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Privacy settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: isUp ? "shield.lefthalf.filled" : "shield.slash")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(isUp ? AnyShapeStyle(LinearGradient.neutrin) : AnyShapeStyle(Color.secondary))
                .frame(width: 84, height: 84)
                .glass(cornerRadius: 26)
            VStack(spacing: 4) {
                Text(isUp ? "Shields are up" : "Shields are down")
                    .font(.title3.weight(.bold))
                Text(host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Toggle(isOn: Binding(
                get: { store.shieldsEnabled(for: controller.url?.host) },
                set: { store.setShields($0, for: controller.url?.host) }
            )) {
                Text("Block ads & trackers on this site")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(!store.shieldsAreConfigured || host.isEmpty)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .glass(cornerRadius: 18)

            if !store.shieldsAreConfigured {
                Text("Ad and tracker blocking is off for all sites in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var counters: some View {
        HStack(spacing: 12) {
            CounterTile(value: ads.count, title: "Ads blocked", symbol: "rectangle.badge.xmark")
            CounterTile(value: trackers.count, title: "Trackers blocked", symbol: "eye.slash")
        }
    }

    @ViewBuilder
    private var blockedList: some View {
        if !controller.blockedItems.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Blocked on this page")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                ForEach(controller.blockedItems) { item in
                    HStack {
                        Text(item.host)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(item.category == .ads ? "Ad" : "Tracker")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.category == .ads ? Color.orange : Color.neutrinBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((item.category == .ads ? Color.orange : Color.neutrinBlue).opacity(0.12), in: Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                }
            }
            .padding(.bottom, 8)
            .glass(cornerRadius: 20)
        }
    }

    private var protections: some View {
        let settings = store.privacySettings
        let secure = controller.url?.scheme == "https"
        return VStack(spacing: 0) {
            ProtectionRow(symbol: secure ? "lock.fill" : "lock.open",
                          title: secure ? "Secure connection" : "Connection not secure",
                          isOn: secure)
            Divider().padding(.leading, 48)
            ProtectionRow(symbol: "hand.raised", title: "Global Privacy Control", isOn: settings.globalPrivacyControl)
            Divider().padding(.leading, 48)
            ProtectionRow(symbol: "link", title: "Tracking parameters removed from links", isOn: settings.removeTrackingParameters)
            Divider().padding(.leading, 48)
            ProtectionRow(symbol: "eye.slash", title: "Private tab (nothing saved)", isOn: controller.isPrivate)
        }
        .glass(cornerRadius: 20)
    }
}

private struct CounterTile: View {
    let value: Int
    let title: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.neutrinBlue)
            Text(value.formatted())
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glass(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}

private struct ProtectionRow: View {
    let symbol: String
    let title: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(isOn ? Color.neutrinBlue : Color.secondary)
            Text(title).font(.subheadline)
            Spacer()
            Image(systemName: isOn ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isOn ? Color.green : Color.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
