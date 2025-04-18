//
//  main.swift
//  Block Mount
//
//  Created by Kamala Kannan N G on 08/04/25.
//

import Foundation
import DiskArbitration
import IOKit.usb

struct USBInfo {
    let vendorID: Int
    let productID: Int
    let serialNumber: String
}

class DiskMountBlocker {
    private var session: DASession?
    private var iterator: io_iterator_t = 0
    private var notificationPort: IONotificationPortRef?
    var blockedUSBs: [USBInfo] = []
    
    init?() {
        session = DASessionCreate(kCFAllocatorDefault)
        
        guard let session = session else {
            print("Failed to create Disk Arbitration session.")
            return
        }
        
        DASessionSetDispatchQueue(session, DispatchQueue.global(qos: .default))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
        DARegisterDiskMountApprovalCallback(session, nil, mountApprovalCallback, selfPointer)
        
        let blockedUSB = USBInfo(vendorID: 1921, productID: 21931, serialNumber: "00002324122424065600")
        blockedUSBs.append(blockedUSB)
    }
    
    func findUSBDevice(from media: io_object_t) -> io_object_t? {
        var iterator: io_iterator_t = 0
        IORegistryEntryGetParentIterator(media, kIOServicePlane, &iterator)
        
        defer { IOObjectRelease(iterator) }
        
        while case let parent = IOIteratorNext(iterator), parent != IO_OBJECT_NULL {
            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(parent, &className)
            let classString = String(cString: className)
            if classString == "IOUSBHostDevice" {
                print("IOUSBDevice found!")
                return parent
            }
            
            if let media = findUSBDevice(from: parent) {
                IOObjectRelease(parent)
                return media
            }
            IOObjectRelease(parent)
        }
        
        return nil
    }
}

func mountApprovalCallback(disk: DADisk, context: UnsafeMutableRawPointer?) -> Unmanaged<DADissenter>? {
    let device = DADiskCopyIOMedia(disk)
    var className = [CChar](repeating: 0, count: 128)
    let res = IOObjectGetClass(device, &className)
        
    if res == KERN_SUCCESS {
        print(String(cString: className))
    }
    
    guard let context = context else {
        print("Context is nil!")
        return nil
    }
    
    let monitor = Unmanaged<DiskMountBlocker>.fromOpaque(context).takeUnretainedValue()
    guard let IOUSBDevice = monitor.findUSBDevice(from: device) else {
        print("Failed to find the USB device!")
        return nil
    }
    
    defer { IOObjectRelease(IOUSBDevice) }
    
    var properties: Unmanaged<CFMutableDictionary>?
    let result = IORegistryEntryCreateCFProperties(IOUSBDevice, &properties, kCFAllocatorDefault, 0)
    
    guard result == KERN_SUCCESS, let propDict = properties?.takeRetainedValue() as? [String: Any] else {
        print("Failed to get device properties")
        return nil
    }
    
    if let deviceName = propDict["USB Product Name"] {
        print("USB Device : \(deviceName)")
    } else {
        print("USB Product Name not available")
    }
    
    guard let vendorID = propDict["idVendor"] else {
        print("Vendor ID not available")
        return nil
    }
    print("Vendor ID     : \(vendorID)")
    
    guard let productID = propDict["idProduct"] else {
        print("Product ID not available")
        return nil
    }
    print("Product ID    : \(productID)")
    
    guard let serialNumber = propDict["USB Serial Number"] else {
        print("Serial Number not available\n")
        return nil
    }
    print("Serial Number : \(serialNumber)\n")
    
    guard let bsdName = DADiskGetBSDName(disk) else {
        print("bsdName is nil")
        return nil
    }
    
    let diskName = String(cString: bsdName)
    
    for blockedUSB in monitor.blockedUSBs {
        if blockedUSB.vendorID == vendorID as! Int && blockedUSB.productID == productID as! Int && blockedUSB.serialNumber == serialNumber as! String {
            print("Blocking mount for \(diskName)...")
            let dissenter = DADissenterCreate(
                kCFAllocatorDefault,
                DAReturn(kDAReturnNotPermitted),
                "Mounting not permitted for this USB" as CFString
            )
            
            return Unmanaged.passRetained(dissenter)
        } else {
            print("Allowing mount for \(diskName)...")
            return nil
        }
    }
    return nil
}

if DiskMountBlocker() != nil {
    print("Mount Blocker is running...")
    RunLoop.main.run()
} else {
    print("Failed to initialize!")
}
