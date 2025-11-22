//
//  ADBPairingService.swift
//  AndroLaunch
//
//  Created by Aman Raj on 22/11/25.
//

import Foundation
import Network
import Combine
import CoreImage.CIFilterBuiltins

protocol ADBPairingServiceProtocol {
    var pairingStatus: PassthroughSubject<String, Never> { get }
    var isPairing: CurrentValueSubject<Bool, Never> { get }
    
    func startPairing() -> (qrCode: String, password: String)
    func stopPairing()
}

final class ADBPairingService: NSObject, ADBPairingServiceProtocol, NetServiceBrowserDelegate, NetServiceDelegate {
    private let commandExecutor: CommandExecutorProtocol
    private let adbService: ADBServiceProtocol
    private var browser: NWBrowser?
    private var netServiceBrowser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    private var password: String = ""
    private var pairedIP: String?
    
    let pairingStatus = PassthroughSubject<String, Never>()
    let isPairing = CurrentValueSubject<Bool, Never>(false)
    
    private var cancellables = Set<AnyCancellable>()
    
    init(commandExecutor: CommandExecutorProtocol, adbService: ADBServiceProtocol) {
        self.commandExecutor = commandExecutor
        self.adbService = adbService
        super.init()
    }
    
    func startPairing() -> (qrCode: String, password: String) {
        // 1. Generate Password
        let randomCode = Int.random(in: 100000...999999)
        self.password = String(randomCode)
        
        // 2. Generate QR String
        // Format: WIFI:T:ADB;S:ADBQR-connectPhoneOverWifi;P:<password>;;
        let qrString = "WIFI:T:ADB;S:ADBQR-connectPhoneOverWifi;P:\(self.password);;"
        
        // 3. Start mDNS Discovery
        startBrowsing()
        
        isPairing.send(true)
        pairingStatus.send("Waiting for device to scan QR code...")
        
        return (qrString, self.password)
    }
    
    func stopPairing() {
        browser?.cancel()
        browser = nil
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        resolvingServices.forEach { $0.stop() }
        resolvingServices.removeAll()
        isPairing.send(false)
        pairingStatus.send("Pairing stopped.")
    }
    
    private func startBrowsing() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_adb-tls-pairing._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: parameters)
        
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Browser ready")
            case .failed(let error):
                self?.pairingStatus.send("Discovery failed: \(error.localizedDescription)")
                self?.stopPairing()
            default:
                break
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            for result in results {
                if case let .service(name, type, domain, interface) = result.endpoint {
                    print("Found service: \(name) \(type) \(domain)")
                    self.resolveEndpoint(result.endpoint)
                }
            }
        }
        
        self.browser = browser
        browser.start(queue: .main)
    }
    
    private func resolveEndpoint(_ endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: params)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = innerEndpoint {
                    
                    // Convert host to string
                    var ipString: String?
                    var isIPv6 = false
                    switch host {
                    case .ipv4(let ipv4):
                        ipString = "\(ipv4)"
                    case .ipv6(let ipv6):
                        ipString = "\(ipv6)"
                        isIPv6 = true
                    default:
                        break
                    }
                    
                    if let ip = ipString {
                        // Keep the scope ID (e.g. %en0) for IPv6 link-local addresses
                        var ipToUse = ip
                        if isIPv6 {
                            ipToUse = "[\(ip)]"
                        }
                        self?.pairDevice(ip: ipToUse, port: port.rawValue)
                        connection.cancel()
                    }
                }
            case .failed(_):
                connection.cancel()
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func pairDevice(ip: String, port: UInt16) {
        guard let adbPath = adbService.adbPath else {
            pairingStatus.send("ADB not found. Please ensure ADB is installed.")
            return
        }
        
        pairingStatus.send("Found device at \(ip):\(port). Pairing...")
        
        // Quote the IP:Port to prevent shell globbing issues with brackets
        let command = "\(adbPath) pair \"\(ip):\(port)\" \(self.password)"
        print("Executing: \(command)")
        
        commandExecutor.execute(command)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.pairingStatus.send("Pairing failed: \(error.localizedDescription)")
                }
            } receiveValue: { [weak self] output in
                print("Pairing output: \(output)")
                if output.contains("Successfully paired to") {
                    self?.pairingStatus.send("Successfully paired! Connecting...")
                    self?.pairedIP = ip
                    self?.startConnectDiscovery()
                } else {
                    self?.pairingStatus.send("Pairing output: \(output)")
                }
            }
            .store(in: &cancellables)
    }
    
    private func startConnectDiscovery() {
        print("Starting connect discovery using NetServiceBrowser")
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.includesPeerToPeer = true
        browser.searchForServices(ofType: "_adb-tls-connect._tcp", inDomain: "local.")
        self.netServiceBrowser = browser
    }
    
    // MARK: - NetServiceBrowserDelegate
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("Found connect service: \(service.name)")
        service.delegate = self
        service.schedule(in: .main, forMode: .common)
        service.resolve(withTimeout: 10.0)
        resolvingServices.append(service)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("NetServiceBrowser failed: \(errorDict)")
    }
    
    // MARK: - NetServiceDelegate
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        print("Resolved service: \(sender.hostName ?? "nil") : \(sender.port)")
        
        if let host = sender.hostName, sender.port != -1 {
            // Try to connect using hostname first
            // Note: hostName usually includes trailing dot, e.g. "device.local."
            var cleanHost = host
            if cleanHost.hasSuffix(".") {
                cleanHost = String(cleanHost.dropLast())
            }
            self.connectDevice(ip: cleanHost, port: UInt16(sender.port))
            
            // Also try to extract IP addresses if hostname fails?
            // For now, let's rely on hostname or try to parse addresses if needed.
            // Parsing sockaddr is verbose in Swift.
        }
        
        if let index = resolvingServices.firstIndex(of: sender) {
            resolvingServices.remove(at: index)
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("Failed to resolve service \(sender.name): \(errorDict)")
        if let index = resolvingServices.firstIndex(of: sender) {
            resolvingServices.remove(at: index)
        }
    }
    
    private func connectDevice(ip: String, port: UInt16) {
        guard let adbPath = adbService.adbPath else { return }
        
        let command = "\(adbPath) connect \"\(ip):\(port)\""
        print("Executing: \(command)")
        
        commandExecutor.execute(command)
            .receive(on: DispatchQueue.main)
            .sink { _ in } receiveValue: { [weak self] output in
                print("Connect output: \(output)")
                if output.contains("connected to") {
                    self?.pairingStatus.send("Connected to \(ip)!")
                    self?.adbService.listDevices()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.stopPairing()
                    }
                }
            }
            .store(in: &cancellables)
    }
}
