//
//  SettingsManager.swift
//  GitlabMenubar
//
//  Created by Antigravity on 18/12/2025.
//

import Foundation

class SettingsManager: ObservableObject {
    @Published var activeTimeMonths: Int {
        didSet {
            UserDefaults.standard.set(activeTimeMonths, forKey: "activeTimeMonths")
        }
    }
    
    init() {
        let savedValue = UserDefaults.standard.integer(forKey: "activeTimeMonths")
        // If no value saved (returns 0), use default of 1
        self.activeTimeMonths = savedValue > 0 ? savedValue : 1
    }
}
