import Foundation
import IOKit
import IOKit.hid
import SwiftUI


// MARK: - Razer Device Protocol
protocol RazerDevice {
    var vendorID: Int { get }
    var productID: Int { get }
    var deviceName: String { get }
    var supportedFeatures: Set<RazerFeature> { get }
}

enum RazerFeature {
    case rgbLighting
    case dpiControl
    case pollingRateControl
    case onboardProfiles
    case macroSupport
}

// MARK: - Razer DeathAdder V2 X Hyperspeed Definition
struct RazerDeathAdderV2XHyperspeed: RazerDevice {
    let vendorID = 0x1532  // Razer Vendor ID
    let productID = 0x009c  // DeathAdder V2 X Hyperspeed Product ID
    let deviceName = "Razer DeathAdder V2 X Hyperspeed"
    let supportedFeatures: Set<RazerFeature> = [
        .dpiControl,
        .pollingRateControl,
        .onboardProfiles
    ]
}

// MARK: - Main Mouse Manager
class RazerMouseManager: ObservableObject {
    @Published var isConnected = false
    @Published var currentDPI = 1800
    @Published var currentPollingRate = 1000
    @Published var batteryLevel: Int?
    @Published var connectionMode: ConnectionMode = .unknown
    
    let availableDPI = [400, 800, 1200, 1600, 1800, 2400, 3200, 4000, 5000, 6400, 8000, 8500, 10000, 12000, 14000, 16000, 20000]
    let availablePollingRates = [125, 500, 1000]
    
    private var hidManager: IOHIDManager?
    private var connectedDevice: IOHIDDevice?
    private let targetDevice = RazerDeathAdderV2XHyperspeed()
    
    // Propriedades para tracking de mudanças
    private var pendingDPIChange: Int?
    private var dpiChangeTimer: Timer?
    
    enum ConnectionMode {
        case wired
        case wireless24GHz
        case bluetooth
        case unknown
    }
    
    init() {
        setupHIDManager()
        scanForDevices()
    }
    
    deinit {
        dpiChangeTimer?.invalidate()
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
    
    // MARK: - HID Manager Setup
    private func setupHIDManager() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else {
            print("Failed to create HID Manager")
            return
        }
        
        // Configure device matching for Razer devices
        let matchingDict = [
            kIOHIDVendorIDKey: targetDevice.vendorID,
            kIOHIDProductIDKey: targetDevice.productID
        ] as CFDictionary
        
        IOHIDManagerSetDeviceMatching(manager, matchingDict)
        
        // Set up callbacks
        let deviceMatchingCallback: IOHIDDeviceCallback = { context, result, sender, device in
            let manager = Unmanaged<RazerMouseManager>.fromOpaque(context!).takeUnretainedValue()
            manager.deviceConnected(device)
        }
        
        let deviceRemovalCallback: IOHIDDeviceCallback = { context, result, sender, device in
            let manager = Unmanaged<RazerMouseManager>.fromOpaque(context!).takeUnretainedValue()
            manager.deviceDisconnected(device)
        }
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovalCallback, context)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
    
    // MARK: - Device Connection Callbacks
    private func deviceConnected(_ device: IOHIDDevice) {
        print("🔌 Razer device connected!")
        
        // Debug device info
        debugDeviceInfo(device)
        
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        
        if usagePage == 0x01 && usage == 0x02 {
            // Interface do mouse - usar para comandos
            print("🖱️ This is the MOUSE interface - using for commands")
            connectedDevice = device
            
            DispatchQueue.main.async {
                self.isConnected = true
                self.detectConnectionMode()
                self.readCurrentSettings()
            }
        }
        
        // Set up input monitoring for DPI changes
        setupInputMonitoring(device)
    }
    
    private func deviceDisconnected(_ device: IOHIDDevice) {
        print("Razer device disconnected!")
        if connectedDevice == device {
            connectedDevice = nil
            DispatchQueue.main.async {
                self.isConnected = false
                self.connectionMode = .unknown
                self.batteryLevel = nil
            }
        }
    }
    
    // MARK: - Input Monitoring
    private func setupInputMonitoring(_ device: IOHIDDevice) {
        print("🎧 Setting up input monitoring for DPI changes...")
        
        let inputCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
            let manager = Unmanaged<RazerMouseManager>.fromOpaque(context!).takeUnretainedValue()
            
            if reportLength > 0 {
                let reportData = Array(UnsafeBufferPointer(start: report, count: Int(reportLength)))
                manager.handleInputReportEnhanced(reportID: Int(reportID), data: reportData)
            }
        }
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        // Register para Input Reports
        var buffer = [UInt8](repeating: 0, count: 64)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            &buffer,
            buffer.count,
            inputCallback,
            context
        )
        
        print("✅ Input monitoring active - try using DPI buttons on mouse!")
    }
    
    // MARK: - Enhanced Input Report Handler
    private func handleInputReportEnhanced(reportID: Int, data: [UInt8]) {
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        
        if reportID != 0 {
            print("📥 Input Report ID \(reportID): \(hexString)")
        }
        
        // Processar apenas Report ID 5 (DPI changes)
        if reportID == 5 && data.count >= 6 {
            print("🎯 DPI Report: \(hexString)")
            
            // Extrair DPI dos bytes 2-3 (BIG ENDIAN)
            let dpiHigh = UInt16(data[2])
            let dpiLow = UInt16(data[3])
            let detectedDPI = Int((dpiHigh << 8) | dpiLow)
            
            if availableDPI.contains(detectedDPI) {
                print("✅ Hardware DPI changed to: \(detectedDPI)")
                
                // SÓ atualizar se realmente detectou mudança do hardware
                DispatchQueue.main.async {
                    self.currentDPI = detectedDPI
                    
                    // Se estava aguardando esta mudança, marcar como confirmada
                    if self.pendingDPIChange == detectedDPI {
                        print("✅ Pending DPI change CONFIRMED by hardware!")
                        self.pendingDPIChange = nil
                        self.dpiChangeTimer?.invalidate()
                    }
                }
            }
        }
    }
    
    // MARK: - CONTROLE DPI COM DEBUG AVANÇADO
    func setDPI(_ dpi: Int) {
        guard availableDPI.contains(dpi) else {
            print("❌ DPI Error: DPI \(dpi) not in available list")
            return
        }
        
        print("🎯 Setting DPI to \(dpi) - FRAGMENTED/ALTERNATIVE APPROACH")
        print("🔄 Current DPI before change: \(currentDPI)")
        
        dpiChangeTimer?.invalidate()
        pendingDPIChange = dpi
        
        // NOVA ABORDAGEM: Comandos fragmentados ou alternativos
        fragmentedCommandApproach(dpi)
    }

    private func fragmentedCommandApproach(_ dpi: Int) {
        print("\n🧩 FRAGMENTED COMMAND APPROACH")
        print("💡 Problem: Output Reports are too small (1-2 bytes), but we need 6 bytes")
        print("💡 Solutions to try:")
        print("   1. Fragment the command into multiple smaller reports")
        print("   2. Try alternative single-byte commands")
        print("   3. Use Feature Reports (which support larger sizes)")
        print("   4. Try Set/Get Report with different approaches")
        
        let dpiHigh = UInt8((dpi >> 8) & 0xFF)
        let dpiLow = UInt8(dpi & 0xFF)
        
        // MÉTODO 1: Comandos fragmentados
        print("\n📋 METHOD 1: Fragmented commands")
        tryFragmentedCommands(dpi: dpi, dpiHigh: dpiHigh, dpiLow: dpiLow)
        
        // MÉTODO 2: Comandos alternativos de 1-2 bytes
        print("\n📋 METHOD 2: Alternative short commands")
        tryAlternativeShortCommands(dpi: dpi, dpiHigh: dpiHigh, dpiLow: dpiLow)
        
        // MÉTODO 3: Feature Reports em interfaces adequadas
        print("\n📋 METHOD 3: Feature Reports on capable interfaces")
        tryFeatureReportsOnCapableDevices(dpi: dpi)
        
        // MÉTODO 4: Abordagem experimental - simulação de controle
        print("\n📋 METHOD 4: Control simulation")
        tryControlSimulation(dpi: dpi)
        
        // Verificação após 2 segundos
        dpiChangeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            self.checkFragmentedCommandSuccess(expectedDPI: dpi)
        }
    }

    // MÉTODO 1: Comandos fragmentados
    private func tryFragmentedCommands(dpi: Int, dpiHigh: UInt8, dpiLow: UInt8) {
        guard let devices = findOutputDevices() else { return }
        
        for (index, device) in devices.enumerated() {
            let maxOutput = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
            let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
            let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
            
            print("🧩 Fragmenting for device \(index): 0x\(String(usagePage, radix: 16))/0x\(String(usage, radix: 16)) (MaxOutput: \(maxOutput))")
            
            if maxOutput == 1 {
                // Para interfaces de 1 byte - enviar sequência
                let fragmentSequence: [UInt8] = [0x05, 0x02, dpiHigh, dpiLow, dpiHigh, dpiLow]
                
                print("   📤 Sending 1-byte sequence:")
                for (step, byte) in fragmentSequence.enumerated() {
                    let command = [byte]
                    print("      Step \(step + 1): \(String(format: "%02X", byte))")
                    sendOutputReportSafe(device: device, command: command)
                    usleep(50000) // 50ms entre fragmentos
                }
                
            } else if maxOutput == 2 {
                // Para interfaces de 2 bytes - enviar pares
                let fragments: [[UInt8]] = [
                    [0x05, 0x02],
                    [dpiHigh, dpiLow],
                    [dpiHigh, dpiLow]
                ]
                
                print("   📤 Sending 2-byte fragments:")
                for (step, fragment) in fragments.enumerated() {
                    print("      Fragment \(step + 1): \(fragment.map { String(format: "%02X", $0) }.joined(separator: " "))")
                    sendOutputReportSafe(device: device, command: fragment)
                    usleep(100000) // 100ms entre fragmentos
                }
            }
            
            usleep(200000) // 200ms entre dispositivos
        }
    }

    // MÉTODO 2: Comandos alternativos curtos
    private func tryAlternativeShortCommands(dpi: Int, dpiHigh: UInt8, dpiLow: UInt8) {
        guard let devices = findOutputDevices() else { return }
        
        // Tentar comandos que podem funcionar com 1-2 bytes
        let shortCommands: [(command: [UInt8], description: String)] = [
            // Comandos de 1 byte
            ([0x05], "DPI command marker"),
            ([0x02], "Command type"),
            ([dpiHigh], "DPI high byte"),
            ([dpiLow], "DPI low byte"),
            
            // Comandos de 2 bytes
            ([0x05, 0x02], "Command header"),
            ([0x05, dpiHigh], "Command + DPI high"),
            ([0x05, dpiLow], "Command + DPI low"),
            ([dpiHigh, dpiLow], "DPI bytes only"),
            ([0x02, dpiHigh], "Type + DPI high"),
            ([0x02, dpiLow], "Type + DPI low"),
            
            // Comandos experimentais
            ([0x01], "Alternative command 1"),
            ([0x03], "Alternative command 3"),
            ([0x04], "Alternative command 4"),
            ([0x01, 0x02], "Alt header 1"),
            ([0x03, 0x04], "Alt header 2")
        ]
        
        for (deviceIndex, device) in devices.enumerated() {
            let maxOutput = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
            let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
            let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
            
            print("🎯 Testing short commands on device \(deviceIndex): 0x\(String(usagePage, radix: 16))/0x\(String(usage, radix: 16))")
            
            for (command, description) in shortCommands {
                if command.count <= maxOutput {
                    print("   📤 [\(description)]: \(command.map { String(format: "%02X", $0) }.joined(separator: " "))")
                    sendOutputReportSafe(device: device, command: command)
                    usleep(50000) // 50ms entre comandos
                }
            }
            
            usleep(200000) // 200ms entre dispositivos
        }
    }

    // MÉTODO 3: Feature Reports em dispositivos capazes
    private func tryFeatureReportsOnCapableDevices(dpi: Int) {
        print("🎯 Trying Feature Reports on devices with adequate size...")
        
        guard let manager = hidManager else { return }
        let deviceSet = IOHIDManagerCopyDevices(manager)
        
        if let deviceSetRef = deviceSet {
            let deviceCount = CFSetGetCount(deviceSetRef)
            var deviceArray = Array<UnsafeRawPointer?>(repeating: nil, count: deviceCount)
            CFSetGetValues(deviceSetRef, &deviceArray)
            
            for i in 0..<deviceCount {
                if let devicePtr = deviceArray[i] {
                    let device = Unmanaged<IOHIDDevice>.fromOpaque(devicePtr).takeUnretainedValue()
                    let maxFeature = IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0
                    let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
                    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
                    
                    if maxFeature >= 6 {
                        print("📤 Feature Report on device \(i): 0x\(String(usagePage, radix: 16))/0x\(String(usage, radix: 16)) (MaxFeature: \(maxFeature))")
                        
                        let dpiHigh = UInt8((dpi >> 8) & 0xFF)
                        let dpiLow = UInt8(dpi & 0xFF)
                        
                        // Comando direto como Feature Report
                        let featureCommand = [0x00, 0x05, 0x02, dpiHigh, dpiLow, dpiHigh, dpiLow]
                        
                        print("   📤 Direct feature command: \(featureCommand.map { String(format: "%02X", $0) }.joined(separator: " "))")
                        sendFeatureReportSafe(device: device, command: featureCommand, maxSize: maxFeature)
                        
                        usleep(200000) // 200ms
                    }
                }
            }
        }
    }

    // MÉTODO 4: Simulação de controle
    private func tryControlSimulation(dpi: Int) {
        print("🎯 Trying control simulation...")
        
        // Tentar usar IOHIDDeviceSetProperty para controlar o mouse
        guard let manager = hidManager else { return }
        let deviceSet = IOHIDManagerCopyDevices(manager)
        
        if let deviceSetRef = deviceSet {
            let deviceCount = CFSetGetCount(deviceSetRef)
            var deviceArray = Array<UnsafeRawPointer?>(repeating: nil, count: deviceCount)
            CFSetGetValues(deviceSetRef, &deviceArray)
            
            for i in 0..<deviceCount {
                if let devicePtr = deviceArray[i] {
                    let device = Unmanaged<IOHIDDevice>.fromOpaque(devicePtr).takeUnretainedValue()
                    let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
                    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
                    
                    print("🧪 Control simulation on device \(i): 0x\(String(usagePage, radix: 16))/0x\(String(usage, radix: 16))")
                    
                    // Tentar definir propriedades customizadas
                    let dpiValue = NSNumber(value: dpi)
                    
                    // Tentar várias chaves possíveis
                    let possibleKeys = [
                        "DPI",
                        "Resolution",
                        "MouseDPI",
                        "RazerDPI",
                        "SensorDPI",
                        kIOHIDPointerResolutionKey as String
                    ]
                    
                    for key in possibleKeys {
                        print("   📤 Setting property '\(key)' to \(dpi)")
                        IOHIDDeviceSetProperty(device, key as CFString, dpiValue)
                        usleep(50000)
                    }
                }
            }
        }
    }

    // Funções auxiliares
    private func findOutputDevices() -> [IOHIDDevice]? {
        guard let manager = hidManager else { return nil }
        let deviceSet = IOHIDManagerCopyDevices(manager)
        var devices: [IOHIDDevice] = []
        
        if let deviceSetRef = deviceSet {
            let deviceCount = CFSetGetCount(deviceSetRef)
            var deviceArray = Array<UnsafeRawPointer?>(repeating: nil, count: deviceCount)
            CFSetGetValues(deviceSetRef, &deviceArray)
            
            for i in 0..<deviceCount {
                if let devicePtr = deviceArray[i] {
                    let device = Unmanaged<IOHIDDevice>.fromOpaque(devicePtr).takeUnretainedValue()
                    let maxOutput = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
                    
                    if maxOutput > 0 {
                        devices.append(device)
                    }
                }
            }
        }
        
        return devices.isEmpty ? nil : devices
    }

    private func sendOutputReportSafe(device: IOHIDDevice, command: [UInt8]) -> Bool {
        guard !command.isEmpty else { return false }
        
        let data = Data(command)
        return data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else { return false }
            
            let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(command[0]), baseAddress, command.count)
            return result == kIOReturnSuccess
        }
    }

    private func sendFeatureReportSafe(device: IOHIDDevice, command: [UInt8], maxSize: Int) -> Bool {
        guard !command.isEmpty else { return false }
        
        var paddedCommand = command
        if maxSize == 90 {
            paddedCommand = padToNinetyBytes(command)
        } else {
            while paddedCommand.count < maxSize && paddedCommand.count < 64 {
                paddedCommand.append(0x00)
            }
        }
        
        let data = Data(paddedCommand)
        return data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else { return false }
            
            let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, baseAddress, paddedCommand.count)
            return result == kIOReturnSuccess
        }
    }


    private func checkFragmentedCommandSuccess(expectedDPI: Int) {
        print("\n🔍 CHECKING FRAGMENTED COMMAND SUCCESS:")
        print("   Expected DPI: \(expectedDPI)")
        print("   Current DPI: \(currentDPI)")
        print("   Pending change: \(pendingDPIChange ?? -1)")
        
        if currentDPI == expectedDPI && pendingDPIChange == nil {
            print("🎉 SUCCESS! One of the fragmented/alternative methods worked!")
            print("✅ Mouse DPI successfully changed via software!")
        } else {
            print("❌ All fragmented approaches failed")
            print("\n💡 FINAL RECOMMENDATIONS:")
            print("1. 🔌 Try connecting mouse via USB cable (if available)")
            print("2. 📱 Check if mouse has different modes (gaming mode, etc.)")
            print("3. 🔍 Use USB packet sniffer to see actual USB traffic")
            print("4. 🧪 Try Razer Synapse software to see if it works")
            print("5. 📚 Check OpenRazer Linux driver source for this specific model")
            
            print("\n🎯 MOST LIKELY CAUSE:")
            print("The mouse may require a specific initialization sequence")
            print("or may only accept DPI changes in certain modes/states.")
        }
        
        pendingDPIChange = nil
    }
    
    // Função experimental para investigar o protocolo
    private func experimentalDPIControl(_ dpi: Int) {
        print("\n🧪 EXPERIMENTAL DPI CONTROL - Investigating protocol...")
        
        let dpiHigh = UInt8((dpi >> 8) & 0xFF)
        let dpiLow = UInt8(dpi & 0xFF)
        
        // TESTE 1: Capturar TODOS os input reports por alguns segundos
        print("\n📋 TEST 1: Monitoring ALL input reports for 3 seconds...")
        startComprehensiveInputMonitoring()
        
        // TESTE 2: Tentar diferentes interfaces para envio
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.testAllInterfaces(dpi: dpi)
        }
        
        // TESTE 3: Tentar protocolo de handshake
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.testHandshakeProtocol(dpi: dpi)
        }
        
        // TESTE 4: Verificação final
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            self.finalDPIVerification(expectedDPI: dpi)
        }
    }
    
    // Monitoramento abrangente de input reports
    private func startComprehensiveInputMonitoring() {
        print("🔍 Starting comprehensive input monitoring...")
        print("💡 Try pressing DPI buttons on your mouse NOW to see the pattern!")
        
        // Capturar de TODAS as interfaces, não só da principal
        guard let manager = hidManager else { return }
        let deviceSet = IOHIDManagerCopyDevices(manager)
        
        if let devices = deviceSet {
            let deviceCount = CFSetGetCount(devices)
            var deviceArray = Array<UnsafeRawPointer?>(repeating: nil, count: deviceCount)
            CFSetGetValues(devices, &deviceArray)
            
            for i in 0..<deviceCount {
                if let devicePtr = deviceArray[i] {
                    let device = Unmanaged<IOHIDDevice>.fromOpaque(devicePtr).takeUnretainedValue()
                    setupEnhancedInputMonitoring(device, interfaceIndex: i)
                }
            }
        }
    }
    
    private func setupEnhancedInputMonitoring(_ device: IOHIDDevice, interfaceIndex: Int) {
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        
        print("🎧 Enhanced monitoring on Interface \(interfaceIndex): UsagePage=0x\(String(usagePage, radix: 16)), Usage=0x\(String(usage, radix: 16))")
        
        let inputCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
            if (reportLength > 0 && reportID != 0) {
                let reportData = Array(UnsafeBufferPointer(start: report, count: Int(reportLength)))
                let hexString = reportData.map { String(format: "%02X", $0) }.joined(separator: " ")
                let interfaceIndex = Int(bitPattern: context) // Recuperar o index
                print("📥 [Interface \(interfaceIndex)] Report ID \(reportID): \(hexString)")
            }
        }
        
        let context = UnsafeMutableRawPointer(bitPattern: interfaceIndex) // Usando index como context
        
        var buffer = [UInt8](repeating: 0, count: 64)
        IOHIDDeviceRegisterInputReportCallback(device, &buffer, buffer.count, inputCallback, context)
    }
    
    // Testar envio em TODAS as interfaces
    private func testAllInterfaces(dpi: Int) {
        print("\n📋 TEST 2: Sending commands to ALL interfaces...")
        
        guard let manager = hidManager else { return }
        let deviceSet = IOHIDManagerCopyDevices(manager)
        
        let dpiHigh = UInt8((dpi >> 8) & 0xFF)
        let dpiLow = UInt8(dpi & 0xFF)
        
        if let devices = deviceSet {
            let deviceCount = CFSetGetCount(devices)
            var deviceArray = Array<UnsafeRawPointer?>(repeating: nil, count: deviceCount)
            CFSetGetValues(devices, &deviceArray)
            
            for i in 0..<deviceCount {
                if let devicePtr = deviceArray[i] {
                    let device = Unmanaged<IOHIDDevice>.fromOpaque(devicePtr).takeUnretainedValue()
                    testSingleInterface(device: device, interfaceIndex: i, dpi: dpi)
                    usleep(200000) // 200ms entre interfaces
                }
            }
        }
    }
    
    private func testSingleInterface(device: IOHIDDevice, interfaceIndex: Int, dpi: Int) {
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let maxOutput = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        let maxFeature = IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0
        
        print("🧪 Testing Interface \(interfaceIndex): 0x\(String(usagePage, radix: 16))/0x\(String(usage, radix: 16)) (Out:\(maxOutput), Feat:\(maxFeature))")
        
        let dpiHigh = UInt8((dpi >> 8) & 0xFF)
        let dpiLow = UInt8(dpi & 0xFF)
        
        // Tentar Output Report se disponível
        if maxOutput > 0 {
            let outputCommands: [[UInt8]] = [
                [0x05, 0x02, dpiHigh, dpiLow, dpiHigh, dpiLow],
                [0x01, 0x02, dpiHigh, dpiLow, dpiHigh, dpiLow],
                [0x02, 0x02, dpiHigh, dpiLow, dpiHigh, dpiLow],
                [0x03, 0x02, dpiHigh, dpiLow, dpiHigh, dpiLow]
            ]
            
            for (index, command) in outputCommands.enumerated() {
                if command.count <= maxOutput {
                    print("   📤 Output[\(index)]: \(command.map { String(format: "%02X", $0) }.joined(separator: " "))")
                    sendOutputReportSafe(device: device, command: command)
                    usleep(50000) // 50ms entre comandos
                }
            }
        }
        
        // Tentar Feature Report se disponível
        if maxFeature > 0 {
            let featureCommands: [[UInt8]] = [
                [0x00, 0x05, 0x02, dpiHigh, dpiLow, dpiHigh, dpiLow],
                [0x00, 0x1F, 0x04, 0x07, 0x04, 0x01, 0x00, dpiHigh, dpiLow]
            ]
            
            for (index, command) in featureCommands.enumerated() {
                print("   📤 Feature[\(index)]: \(command.map { String(format: "%02X", $0) }.joined(separator: " "))")
                sendFeatureReportSafe(device: device, command: command, maxSize: maxFeature)
                usleep(50000) // 50ms entre comandos
            }
        }
    }
    
    // Testar protocolo de handshake
    private func testHandshakeProtocol(dpi: Int) {
        print("\n📋 TEST 3: Testing handshake protocol...")
        
        guard let device = findBestDevice() else {
            print("❌ No suitable device found for handshake")
            return
        }
        
        let dpiHigh = UInt8((dpi >> 8) & 0xFF)
        let dpiLow = UInt8(dpi & 0xFF)
        
        // Sequência de handshake experimental
        let handshakeSequence: [[UInt8]] = [
            // 1. Possível comando de "wake up"
            [0x01, 0x00, 0x00, 0x00],
            
            // 2. Comando de inicialização
            [0x05, 0x01, 0x00, 0x00, 0x00, 0x00],
            
            // 3. Comando DPI
            [0x05, 0x02, dpiHigh, dpiLow, dpiHigh, dpiLow],
            
            // 4. Possível comando de confirmação
            [0x05, 0x03, 0x00, 0x00, 0x00, 0x00]
        ]
        
        for (index, command) in handshakeSequence.enumerated() {
            print("🤝 Handshake step \(index + 1): \(command.map { String(format: "%02X", $0) }.joined(separator: " "))")
            sendOutputReportSafe(device: device, command: command)
            usleep(100000) // 100ms entre passos
        }
    }
    
    // Verificação final SEM atualizar currentDPI automaticamente
    private func finalDPIVerification(expectedDPI: Int) {
        print("\n🔍 FINAL VERIFICATION:")
        print("   Expected DPI: \(expectedDPI)")
        print("   Current DPI in code: \(currentDPI)")
        print("   Pending DPI change: \(pendingDPIChange ?? -1)")
        
        // IMPORTANTE: Só considerar sucesso se recebeu um Input Report confirmando
        if currentDPI == expectedDPI && pendingDPIChange == nil {
            print("✅ DPI change appears successful based on input reports")
        } else {
            print("❌ DPI change NOT confirmed by mouse hardware")
            print("💡 Try pressing the physical DPI button to see the difference")
            
            // Reset currentDPI para o valor real se não houve confirmação
            if let pending = pendingDPIChange {
                print("🔄 Pending DPI change was not confirmed by hardware: \(pending)")
                // Não alterar currentDPI aqui - deixar como estava
            }
        }
        
        pendingDPIChange = nil
    }
    // Encontrar o melhor device para testes
    private func findBestDevice() -> IOHIDDevice? {
        // Priorizar a interface que recebe Input Reports
        if let device = findInputReportDevice() {
            return device
        }
        
        // Fallback para interface do mouse
        return findMouseInterface()
    }
    
    // MARK: - FUNÇÕES DE SUPORTE ORIGINAIS
    private func findInputReportDevice() -> IOHIDDevice? {
        guard let manager = hidManager else { return nil }
        let deviceSet = IOHIDManagerCopyDevices(manager)
        
        if let devices = deviceSet {
            let deviceCount = CFSetGetCount(devices)
            var deviceArray = Array<UnsafeRawPointer?>(repeating: nil, count: deviceCount)
            CFSetGetValues(devices, &deviceArray)
            
            for i in 0..<deviceCount {
                if let devicePtr = deviceArray[i] {
                    let device = Unmanaged<IOHIDDevice>.fromOpaque(devicePtr).takeUnretainedValue()
                    let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
                    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
                    let maxInputReport = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
                    let maxOutputReport = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
                    
                    // Procurar interface que pode receber os reports que você intercepta
                    if usagePage == 0x59 && usage == 0x1 && maxInputReport >= 2 && maxOutputReport >= 1 {
                        print("🎯 Using interface that receives DPI reports: UsagePage=0x59, Usage=0x1")
                        return device
                    }
                }
            }
        }
        
        print("❌ No suitable input report device found")
        return nil
    }
    
    private func findMouseInterface() -> IOHIDDevice? {
        guard let manager = hidManager else { return nil }
        let deviceSet = IOHIDManagerCopyDevices(manager)
        
        if let devices = deviceSet {
            let deviceCount = CFSetGetCount(devices)
            var deviceArray = Array<UnsafeRawPointer?>(repeating: nil, count: deviceCount)
            CFSetGetValues(devices, &deviceArray)
            
            for i in 0..<deviceCount {
                if let devicePtr = deviceArray[i] {
                    let device = Unmanaged<IOHIDDevice>.fromOpaque(devicePtr).takeUnretainedValue()
                    let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
                    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
                    let maxFeature = IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0
                    
                    // Interface do mouse com 90 bytes de Feature Report
                    if usagePage == 0x01 && usage == 0x02 && maxFeature == 90 {
                        print("🎯 Using mouse interface with 90-byte Feature Reports")
                        return device
                    }
                }
            }
        }
        
        return nil
    }
    
    private func padToNinetyBytes(_ command: [UInt8]) -> [UInt8] {
        var padded = command
        
        // Pad até 88 bytes (deixando espaço para checksum e byte final)
        while padded.count < 88 {
            padded.append(0x00)
        }
        
        // Calcular checksum (XOR dos bytes 2-87)
        let checksum = padded[2..<88].reduce(0) { $0 ^ $1 }
        padded.append(checksum)
        padded.append(0x00) // Byte final
        
        return padded
    }
    
    // MARK: - Polling Rate Control
    func setPollingRate(_ rate: Int) {
        guard availablePollingRates.contains(rate) else { return }
        
        print("Setting polling rate to: \(rate) Hz")
        
        guard let device = findMouseInterface() else {
            print("❌ No device found for polling rate")
            return
        }
        
        let rateValue: UInt8
        switch rate {
        case 125: rateValue = 0x08
        case 500: rateValue = 0x02
        case 1000: rateValue = 0x01
        default: rateValue = 0x01
        }
        
        // OpenRazer polling rate command
        let pollingCommand: [UInt8] = [
            0x00, 0x1F, 0x00, 0x00, 0x01, 0x04, 0x00, 0x01, rateValue
        ]
        
        sendFeatureReportSafe(device: device, command: pollingCommand, maxSize: 90)
        
        DispatchQueue.main.async {
            self.currentPollingRate = rate
        }
    }
    
    // MARK: - Utility Functions
    func resetToDefault() {
        setDPI(1800)
        setPollingRate(1000)
    }
    
    private func detectConnectionMode() {
        connectionMode = .wireless24GHz // Assumindo 2.4GHz por padrão
    }
    
    private func readCurrentSettings() {
        currentDPI = 1800  // Valor padrão
        currentPollingRate = 1000  // Valor padrão
        
        if connectionMode != .wired {
            batteryLevel = Int.random(in: 20...100)
        }
    }
    
    private func debugDeviceInfo(_ device: IOHIDDevice) {
        print("🔍 Device Debug Info:")
        
        if let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int {
            print("   Vendor ID: 0x\(String(vendorID, radix: 16))")
        }
        
        if let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int {
            print("   Product ID: 0x\(String(productID, radix: 16))")
        }
        
        if let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
            print("   Product: \(productName)")
        }
        
        if let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int {
            print("   Usage Page: 0x\(String(usagePage, radix: 16))")
        }
        
        if let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int {
            print("   Usage: 0x\(String(usage, radix: 16))")
        }
        
        if let maxInputReportSize = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int {
            print("   Max Input Report Size: \(maxInputReportSize)")
        }
        
        if let maxOutputReportSize = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int {
            print("   Max Output Report Size: \(maxOutputReportSize)")
        }
        
        if let maxFeatureReportSize = IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int {
            print("   Max Feature Report Size: \(maxFeatureReportSize)")
        }
    }
    
    func scanForDevices() {
        guard let manager = hidManager else { return }
        
        let deviceSet = IOHIDManagerCopyDevices(manager)
        if let devices = deviceSet {
            let deviceCount = CFSetGetCount(devices)
            if deviceCount > 0 {
                print("Found \(deviceCount) Razer devices")
            }
        }
    }
    
    
}
