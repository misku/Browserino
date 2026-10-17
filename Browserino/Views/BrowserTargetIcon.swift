//
//  BrowserTargetIcon.swift
//  Browserino
//

import SwiftUI

/// The browser's icon, badged with the profile picture when there is one, so that
/// several profiles of the same browser stay distinguishable at a glance.
struct BrowserTargetIcon: View {
    let target: BrowserTarget
    var badgeSize: CGFloat = 14

    /// Firefox's own container colours.
    private static func color(_ name: String) -> Color {
        switch name {
        case "blue": Color(red: 0.22, green: 0.68, blue: 1)
        case "turquoise": Color(red: 0, green: 0.78, blue: 0.6)
        case "green": Color(red: 0.32, green: 0.8, blue: 0)
        case "yellow": Color(red: 1, green: 0.8, blue: 0)
        case "orange": Color(red: 1, green: 0.62, blue: 0)
        case "red": Color(red: 1, green: 0.38, blue: 0.24)
        case "pink": Color(red: 1, green: 0.29, blue: 0.85)
        case "purple": Color(red: 0.69, green: 0.32, blue: 0.96)
        default: Color.gray
        }
    }

    /// The closest SF Symbol to each of Firefox's container icons.
    private static func symbol(_ name: String) -> String {
        switch name {
        case "fingerprint": "touchid"
        case "briefcase": "briefcase.fill"
        case "dollar": "dollarsign"
        case "cart": "cart.fill"
        case "gift": "gift.fill"
        case "vacation": "airplane"
        case "food": "fork.knife"
        case "fruit": "leaf.fill"
        case "pet": "pawprint.fill"
        case "tree": "tree.fill"
        case "chill": "cup.and.saucer.fill"
        case "fence": "square.grid.3x3.fill"
        default: "circle.fill"
        }
    }

    var body: some View {
        Image(nsImage: target.icon)
            .resizable()
            .overlay(alignment: .bottomTrailing) {
                if let container = target.firefoxContainer {
                    // Containers wear their colour and icon, as tabs do in Firefox.
                    Circle()
                        .fill(Self.color(container.color))
                        .overlay {
                            Image(systemName: Self.symbol(container.icon))
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.white)
                                .padding(badgeSize * 0.22)
                        }
                        .frame(width: badgeSize, height: badgeSize)
                        .overlay {
                            Circle().strokeBorder(.background, lineWidth: 1.5)
                        }
                        .offset(x: badgeSize / 4, y: badgeSize / 4)
                } else if let avatar = target.chromiumProfile?.avatar,
                   let image = ChromiumProfileService.avatarImage(avatar) {
                    Image(nsImage: image)
                        .resizable()
                        .clipShape(.circle)
                        .frame(width: badgeSize, height: badgeSize)
                        .overlay {
                            Circle().strokeBorder(.background, lineWidth: 1.5)
                        }
                        .offset(x: badgeSize / 4, y: badgeSize / 4)
                }
            }
    }
}
