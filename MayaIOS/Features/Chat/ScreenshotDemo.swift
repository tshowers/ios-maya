import Foundation

/// Debug-only: `-screenshotDemo 1` or `-screenshotDemo 2` opens Maya on a
/// real conversation, for App Store screenshots of the app in use (App
/// Review 2.3.3). The replies are Maya's actual answers from the live
/// advice service (captured 2026-09-30), not written by hand.
/// Always off in Release builds.
enum ScreenshotDemo {
    static var conversation: [ChatMessage]? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshotDemo") else { return nil }
        let turns = index + 1 < arguments.count ? (Int(arguments[index + 1]) ?? 1) : 1
        return Array(messages.prefix(turns * 2))
        #else
        return nil
        #endif
    }

    private static let messages: [ChatMessage] = [
        ChatMessage(role: .user, content: "I run a small bookkeeping firm for restaurants. Can you help me sharpen my message?"),
        ChatMessage(role: .director, content: """
Absolutely! For a bookkeeping firm focused on restaurants, clarity and specificity in your messaging are key. Here are a few suggestions to sharpen your message:

1. **Highlight Pain Points**: Emphasize common challenges that restaurants face, like cash flow management, tax compliance, and time-consuming paperwork. For example, "We help restaurants streamline their finances so you can focus on serving great food."

2. **Showcase Expertise**: Position your firm as a specialist in the restaurant industry. You might say, "With years of experience in restaurant bookkeeping, we understand your unique needs and the intricacies of your business."

3. **Offer Solutions**: Be clear about what you provide. For instance, mention services like payroll management, expense tracking, and financial reporting tailored for restaurants.

4. **Call to Action**: Encourage potential clients to reach out. Something like, "Let’s simplify your finances together—schedule a free consultation today!" can be effective.

Try to weave these elements into your existing messaging, and let me know if you want to brainstorm specific phrases or taglines!
"""),
        ChatMessage(role: .user, content: "Which restaurants should I go after first, and how do I reach them?"),
        ChatMessage(role: .director, content: """
To effectively target restaurants, start with a mix of local favorites and those that might be struggling, as they often need financial help the most. Look for:

1. **Independent Restaurants**: These often have tighter budgets and may not have a dedicated bookkeeper.
2. **New Restaurants**: They might need guidance on setting up their financial processes.
3. **Restaurants with Recent News**: If a restaurant has been in the news for renovations, new ownership, or expansions, they could be looking for support.

For reaching out to them:
- **Email Campaigns**: Craft personalized emails that address their specific needs and challenges. Use your refined messaging to resonate with them.
- **Social Media**: Engage with local restaurant owners on platforms like Instagram and Facebook. Showcase your expertise by sharing tips or success stories.
- **Networking Events**: Attend local food and beverage events or trade shows to meet restaurant owners in person.

Start by identifying 10-15 restaurants in your area that fit these criteria. Once you have that list, we can craft targeted outreach messages for each.
"""),
    ]
}
