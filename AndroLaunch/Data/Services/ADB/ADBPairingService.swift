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
    
    func startPairing() -> (qrCode: String, password: String)
    func stopPairing()
}

final class ADBPairingService: NSObject, ADBPairingServiceProtocol, NetServiceBrowserDelegate, NetServiceDelegate {
    private let commandExecutor: CommandExecutorProtocol
    private let adbService: ADBServiceProtocol
    
    // Networking
    private var pairingBrowser: NWBrowser? // For _adb-tls-pairing
    private var connectBrowser: NetServiceBrowser? // For _adb-tls-connect
    private var resolvingServices: [NetService] = [] // For NetService (connect discovery)
    private var activePairingConnections: [NWConnection] = [] // For NWConnection (pairing discovery)
    
    // State
    private var password: String = ""
    
    // Deduplication - for the current single pairing attempt flow
    private var processedPairingEndpoints = Set<NWEndpoint>() // To not repeatedly try to pair the same device
    private var processedConnectHosts = Set<String>() // To not repeatedly try to connect to the same device
    
    let pairingStatus = PassthroughSubject<String, Never>()
    let isPairing = CurrentValueSubject<Bool, Never>(false)
    
    private var cancellables = Set<AnyCancellable>()
    
    init(commandExecutor: CommandExecutorProtocol, adbService: ADBServiceProtocol) {
        self.commandExecutor = commandExecutor
        self.adbService = adbService
        super.init()
    }
    
    func startPairing() -> (qrCode: String, password: String) {
        // Stop any previous pairing/discovery efforts cleanly before starting a new one
        stopPairing() // Ensure a clean slate

        // 1. Generate Password
        let randomCode = Int.random(in: 100000...999999)
        self.password = String(randomCode)
        
        // 2. Generate QR String
        let qrString = "WIFI:T:ADB;S:ADBQR-connectPhoneOverWifi;P:\(self.password);;"
        
        // 3. Start mDNS Discovery for pairing services
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
        
        cancellables.removeAll() // Clear all Combine subscriptions
        
        isPairing.send(false)
        pairingStatus.send("Pairing stopped.")
    }
    
    // MARK: - Pairing Discovery (_adb-tls-pairing._tcp using NWBrowser)
    
    private func startPairingDiscovery() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_adb-tls-pairing._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: parameters)
        
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                print("ADBPairingService: NWBrowser state failed: \(error.localizedDescription). Stopping pairing.")
                self?.pairingStatus.send("Discovery failed: \(error.localizedDescription)")
                self?.stopPairing() // Stop the entire pairing flow on critical browser failure
            case .ready:
                print("ADBPairingService: NWBrowser is ready for pairing services.")
            case .cancelled:
                print("ADBPairingService: NWBrowser cancelled for pairing services.")
            case .setup, .waiting: // Log other states but don't stop pairing
                print("ADBPairingService: NWBrowser pairing state: \(state)")
            @unknown default:
                print("ADBPairingService: NWBrowser pairing unknown state: \(state)")
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            
            for change in changes {
                switch change {
                case .added(let result):
                    self.handleNewPairingResult(result)
                case .removed(let result):
                    print("ADBPairingService: Pairing Browser removed result: \(result.endpoint)")
                    self.processedPairingEndpoints.remove(result.endpoint) // Allow re-discovery later
                default:
                    break // Ignore changed results for now
                }
            }
        }
        
        self.pairingBrowser = browser
        browser.start(queue: .main)
    }
    
    private func handleNewPairingResult(_ result: NWBrowser.Result) {
        // Deduplication: Check if we processed this endpoint already in this session
        guard !processedPairingEndpoints.contains(result.endpoint) else {
            print("ADBPairingService: Pairing endpoint already processed: \(result.endpoint)")
            return
        }
        processedPairingEndpoints.insert(result.endpoint)
        
        if case let .service(name, _, _, _) = result.endpoint {
            print("ADBPairingService: Found new pairing service: \(name)")
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
                print("ADBPairingService: Pairing connection ready for endpoint: \(endpoint)")
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = innerEndpoint {
                    
                    if case .ipv4(let ipv4) = host {
                        var ipString = "\(ipv4)"
                        if let scopeIndex = ipString.firstIndex(of: "%") {
                            ipString = String(ipString[..<scopeIndex])
                        }
                        
                        print("ADBPairingService: Resolved IPv4 (Cleaned): \(ipString) for pairing.")
                        self.pairDevice(ip: ipString, port: port.rawValue)
                        
                        connection.cancel()
                        self.cleanupPairingConnection(connection)
                    } else {
                        print("ADBPairingService: Resolved host for pairing is not IPv4: \(host). Cancelling.")
                        connection.cancel()
                        self.cleanupPairingConnection(connection)
                    }
                } else {
                    print("ADBPairingService: Failed to get remote endpoint from pairing connection path. Cancelling.")
                    connection.cancel()
                    self.cleanupPairingConnection(connection)
                }
            case .failed(let error):
                print("ADBPairingService: Pairing connection to \(endpoint) failed: \(error.localizedDescription). Cancelling.")
                connection.cancel()
                self.cleanupPairingConnection(connection)
            case .cancelled:
                print("ADBPairingService: Pairing connection to \(endpoint) cancelled.")
                self.cleanupPairingConnection(connection)
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func cleanupPairingConnection(_ connection: NWConnection) {
        if let idx = self.activePairingConnections.firstIndex(where: { $0 === connection }) {
            self.activePairingConnections.remove(at: idx)
            print("ADBPairingService: Cleaned up pairing connection.")
        }
    }
    
    private func pairDevice(ip: String, port: UInt16) {
        guard let adbPath = adbService.adbPath else {
            print("ADBPairingService: ADB path not available, cannot pair.")
            pairingStatus.send("ADB tool not found. Please ensure it's installed.")
            stopPairing() // Fail early if ADB is missing
            return
        }
        
        pairingStatus.send("Attempting to pair with \(ip):\(port)...")
        
        let command = "\(adbPath) pair \"\(ip):\(port)\" \(self.password)"
        print("ADBPairingService: Executing pairing command: \(command)")
        
        commandExecutor.execute(command)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    print("ADBPairingService: Pairing command failed: \(error.localizedDescription)")
                    self?.pairingStatus.send("Pairing failed for \(ip): \(error.localizedDescription)")
                    self?.stopPairing() // Stop if pairing command itself failed
                }
            } receiveValue: { [weak self] output in
                print("ADBPairingService: Pairing command output for \(ip): \(output)")
                
                if output.contains("Successfully paired to") {
                    self?.pairingStatus.send("Successfully paired with \(ip)! Waiting for device to appear as connectable...")
                    // Pairing is done. Stop the pairing browser and start looking for the connect service.
                    self?.pairingBrowser?.cancel()
                    self?.pairingBrowser = nil
                    
                    // Start connect discovery now, it will pick up the newly paired device
                    self?.startConnectDiscovery()
                    
                } else if output.contains("Failed") || output.contains("protocol fault") {
                    self?.pairingStatus.send("Pairing rejected or timed out for \(ip). Check device and try again.")
                    self?.stopPairing() // Pairing itself failed, so stop the process
                } else {
                    self?.pairingStatus.send("Pairing command returned unexpected output: \(output). Stopping.")
                    self?.stopPairing() // Unexpected output, assume failure and stop
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Connect Discovery (_adb-tls-connect._tcp using NetServiceBrowser)
    
    private func startConnectDiscovery() {
        // Clear any previous connect hosts to allow fresh discovery
        processedConnectHosts.removeAll()
        
        print("ADBPairingService: Starting connect NetServiceBrowser...")
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.includesPeerToPeer = true
        browser.searchForServices(ofType: "_adb-tls-connect._tcp", inDomain: "local.")
        self.connectBrowser = browser
    }
    
    // MARK: NetServiceBrowserDelegate
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("ADBPairingService: Found connect service: \(service.name)")
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 10.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("ADBPairingService: NetServiceBrowser for connect discovery failed: \(errorDict). Stopping pairing.")
        pairingStatus.send("Connect discovery failed. Check network and try again.")
        stopPairing() // Critical failure in connect discovery, stop the process
    }
    
    // MARK: NetServiceDelegate
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        print("ADBPairingService: NetService resolved address for: \(sender.name)")
        
        if let host = sender.hostName, sender.port != -1 {
            var cleanHost = host
            if cleanHost.hasSuffix(".") {
                cleanHost = String(cleanHost.dropLast())
            }
            let connectIdentifier = "\(cleanHost):\(sender.port)"
            
            // Deduplicate connection attempts for this specific session
            guard !processedConnectHosts.contains(connectIdentifier) else {
                print("ADBPairingService: Connect host \(connectIdentifier) already processed.")
                if let index = resolvingServices.firstIndex(of: sender) {
                    resolvingServices.remove(at: index)
                }
                return
            }
            processedConnectHosts.insert(connectIdentifier)
            
            self.connectDevice(ip: cleanHost, port: UInt16(sender.port))
        } else {
            print("ADBPairingService: NetService resolved without valid host or port for: \(sender.name)")
        }
        
        if let index = resolvingServices.firstIndex(of: sender) {
            resolvingServices.remove(at: index)
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("ADBPairingService: NetService did not resolve for \(sender.name): \(errorDict)")
        if let index = resolvingServices.firstIndex(of: sender) {
            resolvingServices.remove(at: index)
        }
    }
    
    private func connectDevice(ip: String, port: UInt16) {
        guard let adbPath = adbService.adbPath else {
            print("ADBPairingService: ADB path not available, cannot connect.")
            pairingStatus.send("ADB tool not found. Cannot connect.")
            stopPairing() // Fail early if ADB is missing
            return
        }
        
        let command = "\(adbPath) connect \"\(ip):\(port)\""
        print("ADBPairingService: Executing connect command: \(command)")
        
        commandExecutor.execute(command)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    print("ADBPairingService: Connect command failed for \(ip): \(error.localizedDescription)")
                    self?.pairingStatus.send("Connection failed for \(ip): \(error.localizedDescription)")
                    self?.stopPairing() // Stop if connect command itself failed
                }
            } receiveValue: { [weak self] output in
                print("ADBPairingService: Connect command output for \(ip): \(output)")
                if output.contains("connected to") || output.contains("already connected") {
                    self?.pairingStatus.send("Connected to \(ip)!")
                    self?.adbService.listDevices() // Refresh list of devices
                    
                    // Successfully connected or already connected, so the pairing process is complete.
                    // Stop the pairing service after a short delay for UI feedback.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        print("ADBPairingService: Successfully connected, stopping pairing process after delay.")
                        self?.stopPairing()
                    }
                } else {
                    print("ADBPairingService: Connect command output did not indicate success for \(ip). Output: \(output)")
                    self?.pairingStatus.send("Connection attempt failed for \(ip): \(output)")
                    self?.stopPairing() // Stop if connection output is not success
                }
            }
            .store(in: &cancellables)
    }
}
