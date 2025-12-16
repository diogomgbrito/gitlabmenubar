//
//  GitlabMenubarApp.swift
//  GitlabMenubar
//
//  Created by Diogo Brito on 16/12/2025.
//

import SwiftUI

@main
struct GitlabMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
      var body: some Scene {
        Settings {
          Text("Settings or main app window")
        }
      }
}
