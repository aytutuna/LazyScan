#if os(macOS)
import LazyScanKit
import Foundation
import Network
import dnssd

// Twin of windows/LazyScan.App/Services/Companion/WindowsDnsSdAdvertiser.cs on the DNS-SD C API.
// NWListener.Service would advertise from the server's own listeners, one per address with no
// interface of its own; DNSServiceRegister takes the interface and the port, as Windows does.

// Name conflicts are settled by mDNSResponder (it renames); a refusal for Local Network access arrives here
// after the registration was accepted.
private let companionRegisterReply: DNSServiceRegisterReply = {
    (_: DNSServiceRef?, _: DNSServiceFlags, error: DNSServiceErrorType, _: UnsafePointer<CChar>?, _: UnsafePointer<CChar>?,
     _: UnsafePointer<CChar>?, context: UnsafeMutableRawPointer?) in
    guard let context, EsclLocalNetwork.isPolicyDenied(error) else { return }
    // Off the advertiser's queue: the host's handler takes its lock, which is held while register waits on that queue.
    let advertiser = Unmanaged<MacDnsSdAdvertiser>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.global().async { advertiser.onPolicyDenied?() }
}

/// Advertises `_lazyscan._tcp` with its TXT record on one interface each, for as long as the host
/// keeps it; the host and address records are the Mac's own (mDNSResponder's).
final class MacDnsSdAdvertiser: DnsSdAdvertiser, @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacDnsSdAdvertiser")
    var onPolicyDenied: (() -> Void)?

    func register(_ registration: DnsSdRegistration) throws -> () -> Void {
        var record: [UInt8] = []
        for key in registration.txt.keys.sorted() {
            let entry = Array("\(key)=\(registration.txt[key] ?? "")".utf8.prefix(255))
            record.append(UInt8(entry.count))
            record.append(contentsOf: entry)
        }
        let queue: DispatchQueue = self.queue
        let context: UnsafeMutableRawPointer = Unmanaged.passRetained(self).toOpaque()
        let service: DNSServiceRef = try queue.sync { () throws -> DNSServiceRef in
            var ref: DNSServiceRef?
            let error: DNSServiceErrorType = record.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> DNSServiceErrorType in
                DNSServiceRegister(&ref, 0, UInt32(registration.interfaceIndex), registration.instanceName,
                                   registration.serviceType, nil, nil, UInt16(registration.port).bigEndian,
                                   UInt16(bytes.count), bytes.baseAddress, companionRegisterReply, context)
            }
            guard Int(error) == kDNSServiceErr_NoError, let started = ref else {
                Unmanaged<MacDnsSdAdvertiser>.fromOpaque(context).release()
                throw NWError.dns(error)
            }
            _ = DNSServiceSetDispatchQueue(started, queue)
            return started
        }
        return {
            queue.async {
                DNSServiceRefDeallocate(service)
                Unmanaged<MacDnsSdAdvertiser>.fromOpaque(context).release()
            }
        }
    }
}
#endif
