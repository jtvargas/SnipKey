//
//  SnipKeyTimerWidgetBundle.swift
//  SnipKeyTimerWidget
//
//  Widget extension entry point. Hosts the AlarmKit timer Live Activity. See INTEGRATIONS.md.
//

import SwiftUI
import WidgetKit

@main
struct SnipKeyTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        SnipKeyTimerLiveActivity()
    }
}
