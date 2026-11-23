import SwiftUI

@main
struct RuuutoApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if CreateGroupDemoView.mode != nil {
                CreateGroupDemoView()
            } else {
                AuthenticationView()
            }
            #else
            AuthenticationView()
            #endif
        }
    }
}
