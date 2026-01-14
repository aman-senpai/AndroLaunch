//
//  ADBPairingService.swift
//  AndroLaunch
//
//  Created by Aman Raj on 22/11/25.
//

import Foundation
import Network
import Combine

protocol ADBPairingServiceProtocol {
    var pairingStatus: PassthroughSubject<String, Never> { get }
    var isPairing: CurrentValueSubject<Bool, Never> { get }
    var pairingComplete: PassthroughSubject<Void, Never> { get } // NEW: Signal for completion
    
    func startPairing() -> (qrCode: String, password: String)
    func stopPairing()
}

final class ADBPairingService: NSObject, ADBPairingServiceProtocol, NetServiceBrowserDelegate, NetServiceDelegate {
    private let commandExecutor: CommandExecutorProtocol
    private let adbService: ADBServiceProtocol
    
    // Networking
    private var pairingBrowser: NWBrowser?
    private var connectBrowser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    private var activePairingConnections: [NWConnection] = []
    
    // State
    private var password: String = ""
    
    // Deduplication
    private var processedPairingEndpoints = Set<NWEndpoint>()
    private var processedConnectHosts = Set<String>()
    
    let pairingStatus = PassthroughSubject<String, Never>()
    let isPairing = CurrentValueSubject<Bool, Never>(false)
    let pairingComplete = PassthroughSubject<Void, Never>() // NEW
    
    private var cancellables = Set<AnyCancellable>()
    
    init(commandExecutor: CommandExecutorProtocol, adbService: ADBServiceProtocol) {
        self.commandExecutor = commandExecutor
        self.adbService = adbService
        super.init()
    }
    
    func startPairing() -> (qrCode: String, password: String) {
        stopPairing() // Ensure clean slate

        // 1. Generate Password
        let randomCode = Int.random(in: 100000...999999)
        self.password = String(randomCode)
        
        // 2. Generate QR String
        let qrString = "WIFI:T:ADB;S:ADBQR-connectPhoneOverWifi;P:\(self.password);;"
        
        // 3. Start Discovery
        print("ADBPairingService: Starting browsing for pairing service...")
        startPairingDiscovery()
        
        isPairing.send(true)
        pairingStatus.send("Waiting for device to scan QR code...")
        
        return (qrString, self.password)
    }
    
    func stopPairing() {
        print("ADBPairingService: stopPairing() called.")
        
        pairingBrowser?.cancel()
        pairingBrowser = nil
        
        activePairingConnections.forEach { $0.cancel() }
        activePairingConnections.removeAll()
        
        connectBrowser?.stop()
        connectBrowser = nil
        resolvingServices.forEach { $0.stop() }
        resolvingServices.removeAll()
        
        processedPairingEndpoints.removeAll()
        processedConnectHosts.removeAll()
        
        cancellables.removeAll()
        
        isPairing.send(false)
        pairingStatus.send("Pairing stopped.")
    }
    
    // MARK: - Pairing Discovery
    
    private func startPairingDiscovery() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_adb-tls-pairing._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: parameters)
        
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                print("ADBPairingService: Browser failed: \(error). Restarting...")
                self?.restartPairingDiscovery()
            default: break
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            for change in changes {
                if case .added(let result) = change {
                    self.handleNewPairingResult(result)
                } else if case .removed(let result) = change {
                    self.processedPairingEndpoints.remove(result.endpoint)
                }
            }
        }
        
        self.pairingBrowser = browser
        browser.start(queue: .main)
    }
    
    private func restartPairingDiscovery() {
        pairingBrowser?.cancel()
        pairingBrowser = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startPairingDiscovery()
        }
    }
    
    private func handleNewPairingResult(_ result: NWBrowser.Result) {
        guard !processedPairingEndpoints.contains(result.endpoint) else { return }
        processedPairingEndpoints.insert(result.endpoint)
        
        if case let .service(name, _, _, _) = result.endpoint {
            pairingStatus.send("Device found. Resolving IP for \(name)...")
            resolvePairingEndpoint(result.endpoint)
        }
    }
    
    private func resolvePairingEndpoint(_ endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        if let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }
        
        let connection = NWConnection(to: endpoint, using: params)
        activePairingConnections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                if let inner = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = inner,
                   case .ipv4(let ipv4) = host {
                    
                    var ipString = "\(ipv4)"
                    if let idx = ipString.firstIndex(of: "%") { ipString = String(ipString[..<idx]) }
                    
                    self.pairDevice(ip: ipString, port: port.rawValue, originEndpoint: endpoint)
                    connection.cancel()
                    self.cleanupConnection(connection)
                } else {
                    connection.cancel()
                    self.cleanupConnection(connection)
                    self.processedPairingEndpoints.remove(endpoint) // Retry
                }
            case .failed:
                connection.cancel()
                self.cleanupConnection(connection)
                self.processedPairingEndpoints.remove(endpoint) // Retry
            default: break
            }
        }
        connection.start(queue: .main)
    }
    
    private func cleanupConnection(_ connection: NWConnection) {
        if let idx = activePairingConnections.firstIndex(where: { $0 === connection }) {
            activePairingConnections.remove(at: idx)
        }
    }
    
    private func pairDevice(ip: String, port: UInt16, originEndpoint: NWEndpoint) {
        guard let adbPath = adbService.adbPath else { return }
        let command = "\(adbPath) pair \"\(ip):\(port)\" \(self.password)"
        
        commandExecutor.execute(command)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure = completion {
                    self?.pairingStatus.send("Pairing error. Retrying...")
                    self?.processedPairingEndpoints.remove(originEndpoint)
                    self?.restartPairingDiscovery()
                }
            } receiveValue: { [weak self] output in
                if output.contains("Successfully paired to") || output.contains("already paired") {
                    self?.pairingStatus.send("Paired with \(ip). Connecting...")
                    self?.pairingBrowser?.cancel() // Stop pairing scan
                    self?.pairingBrowser = nil
                    self?.startConnectDiscovery() // Start connect scan
                } else {
                    self?.pairingStatus.send("Pairing rejected. Retrying...")
                    self?.processedPairingEndpoints.remove(originEndpoint)
                    self?.restartPairingDiscovery()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Connect Discovery
    
    private func startConnectDiscovery() {
        processedConnectHosts.removeAll()
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.includesPeerToPeer = true
        browser.searchForServices(ofType: "_adb-tls-connect._tcp", inDomain: "local.")
        self.connectBrowser = browser
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 10.0)
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        if let host = sender.hostName, sender.port != -1 {
            var cleanHost = host
            if cleanHost.hasSuffix(".") { cleanHost = String(cleanHost.dropLast()) }
            let id = "\(cleanHost):\(sender.port)"
            
            if !processedConnectHosts.contains(id) {
                processedConnectHosts.insert(id)
                connectDevice(ip: cleanHost, port: UInt16(sender.port))
            }
        }
        if let idx = resolvingServices.firstIndex(of: sender) { resolvingServices.remove(at: idx) }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        if let idx = resolvingServices.firstIndex(of: sender) { resolvingServices.remove(at: idx) }
    }
    
    private func connectDevice(ip: String, port: UInt16) {
        guard let adbPath = adbService.adbPath else { return }
        let command = "\(adbPath) connect \"\(ip):\(port)\""
        
        commandExecutor.execute(command)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // On command failure, we just let the browser keep looking
            } receiveValue: { [weak self] output in
                if output.contains("connected to") || output.contains("already connected") {
                    self?.pairingStatus.send("Connected to \(ip)!")
                    self?.adbService.listDevices()
                    
                    // NEW LOGIC: Do NOT stop pairing. Signal completion.
                    self?.pairingComplete.send()
                } else {
                    self?.pairingStatus.send("Connection failed. Waiting...")
                }
            }
            .store(in: &cancellables)
    }
}
