//
//  DeveloperView.swift
//  PegelWatch
//
//  Created by Felix Schick on 28.03.26.
//

import SwiftUI

struct DeveloperView: View {
    
    @State private var store = StationStore.shared
    
    var body: some View {
        Button() {
            NotificationManager.shared.sendAlarmNotification(for: store.watchedStations.first!, currentValue: 2122.2)
        } label: {
            Text("send test notication")
        }
    }
}

#Preview {
    DeveloperView()
}
