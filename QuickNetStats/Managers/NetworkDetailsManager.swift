//
//  NetworkDetailsManager.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-11-08.
//

import Foundation
import Combine
import SystemConfiguration

class NetworkDetailsManager: ObservableObject {
    
    /// The private IP of the machine.
    @Published var privateIP: String?
    
    /// The public IP of this machine.
    @Published var publicIP:String?
        
    /// Populate the published attributes for public and private IP.
    func getAddresses() async {
        
        //Delete the old values
        self.publicIP = nil
        self.privateIP = nil
        
        //Compute new values
        self.publicIP = await fetchPublicIpAddress()
        self.privateIP = getPrivateIPAddress()
    }
    
    /**
     * Fetch the device's public IPV4 address.
     * This function makes an asynchronous network call to `https.api.ipify.org`.
     */
    private func fetchPublicIpAddress() async -> String? {
        
        let url = URL(string: "https://api.ipify.org")!

        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            
            guard let httpResp = resp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return nil
            }
            
            return String(data: data, encoding: .utf8)
            
        } catch {
            print(error)
            return nil
        }
    }
    
    /**
     * Fetch the device's private IP address for a specific interface.
     * This function iterates through the device's network interfaces (like Wi-Fi or Cellular)
     * and returns the first valid IPv4 address found.
     *
     * - Returns: The local IPv4 address as a `String`, or `nil` if not found.
     */
    private func getPrivateIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }
            
            let name = String(cString: interface.ifa_name)
            
            if name.starts(with: "en") {
                
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            socklen_t(0),
                            NI_NUMERICHOST)
                
                address = String(cString: hostname)
                
                break
            }
        }
        
        freeifaddrs(ifaddr)
        
        return address
    }
}

import Playgrounds
#Playground {
    let man = NetworkDetailsManager()
    await man.getAddresses()
}
