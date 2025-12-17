//
//  AboutView.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-12.
//

import SwiftUI

struct AboutView: View {
    
    @ObservedObject var settings:Settings
    @ObservedObject var updateManager = UpdateManager.shared
            
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                
                headerSection()
                
                if updateManager.isLoading {
                    ProgressView("Searching for Updates")
                } else {
                    updatesSection()
                }
                
                footerSection()
                
            }
            .task {
                await updateManager.checkForUpdates()
            }
            .padding()
        }
    }
    
    fileprivate func headerSection() -> some View {
        VStack {
            Image("icon")
                .resizable()
                .scaledToFit()
                .frame(width: 150)
            
            Text("QuickNetStats")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(updateManager.getCurrentVersion())
                .font(.headline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 4) {
                Text("Developed by")
                    .foregroundStyle(.secondary)
                Link("Federico Imberti", destination: URL(string: "https://www.federicoimberti.it")!)
            }
        }
    }
    
    fileprivate func updatesSection() -> some View {
        VStack(spacing: 8) {
            
            Image (systemName: updateManager.isUpdateAvailable ? "arrow.down.circle" : "checkmark.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 35)
            
            Text(updateManager.isUpdateAvailable ? "A New Version is Available!" : "You Are Up To Date!")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            if updateManager.isUpdateAvailable {
                HStack(spacing: 4) {
                    Text(updateManager.getCurrentVersion())
                    Image(systemName: "arrow.right")
                    Text(updateManager.latestVersion ?? updateManager.getCurrentVersion())
                }
                .font(.headline)
                .foregroundStyle(.secondary)
            }
            
        }
    }
    
    fileprivate func footerSection() -> some View {
        VStack {
            Link(destination: URL(string:"https://github.com/FI-153/QuickNetStats")!) {
                Image("github")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50)
            }
            
            Text("This App is fully open source and any contribution is appreciated. If you want to contribute or flag an issue, just head to the GitHub repo!")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
    }
    
}

#Preview {
    AboutView(settings: Settings())
}
