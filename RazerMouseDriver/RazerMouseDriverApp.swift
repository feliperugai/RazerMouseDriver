import SwiftUI

@main
struct RazerMouseApp: App {
    @StateObject private var mouseManager = RazerMouseManager()
    
    var body: some Scene {
        MenuBarExtra("Razer Mouse", systemImage: "computermouse") {
            RazerControlView()
                .environmentObject(mouseManager)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RazerControlView: View {
    @EnvironmentObject var mouseManager: RazerMouseManager
    @State private var selectedColor = Color.red
    @State private var brightness: Double = 1.0
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Razer DeathAdder V2 X Hyperspeed")
                .font(.headline)
                .padding()
            
            Group {
                if mouseManager.isConnected {
                    Text("✅ Mouse Connected")
                        .foregroundColor(.green)
                } else {
                    Text("❌ Mouse Not Found")
                        .foregroundColor(.red)
                }
            }
            .font(.subheadline)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Mouse Settings")
                    .font(.headline)
                
                HStack {
                    Text("DPI:")
                    Picker("DPI", selection: $mouseManager.currentDPI) {
                        ForEach(mouseManager.availableDPI, id: \.self) { dpi in
                            Text("\(dpi)").tag(dpi)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: mouseManager.currentDPI) { dpi in
                        print("🎯 DPI changed in UI to: \(dpi)")
                        mouseManager.setDPI(dpi)
                    }
                }
                
                HStack {
                    Text("Polling Rate:")
                    Picker("Polling Rate", selection: $mouseManager.currentPollingRate) {
                        ForEach(mouseManager.availablePollingRates, id: \.self) { rate in
                            Text("\(rate) Hz").tag(rate)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: mouseManager.currentPollingRate) { rate in
                        mouseManager.setPollingRate(rate)
                    }
                }
            }
            
            Divider()
            
            HStack {
                Button("Refresh Devices") {
                    mouseManager.scanForDevices()
                }
                .buttonStyle(.bordered)
                
                Button("Reset to Default") {
                    mouseManager.resetToDefault()
                }
                .buttonStyle(.bordered)
            }
            
            if let battery = mouseManager.batteryLevel {
                Text("Battery: \(battery)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            mouseManager.scanForDevices()
        }
    }
}

#Preview {
    RazerControlView()
        .environmentObject(RazerMouseManager())
}
