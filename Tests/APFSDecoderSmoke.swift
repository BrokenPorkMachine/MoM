import Foundation
@main
struct APFSDecoderSmoke {
    static func main() {
        let root: [String: Any] = ["Containers": [
            ["ContainerReference": "disk3", "APFSContainerUUID":"abc",
             "PhysicalStores": [["DeviceIdentifier":"disk0s2"]],
             "Volumes": [["DeviceIdentifier":"disk3s1", "Name":"Macintosh HD", "Roles":["System"]],
                         ["DeviceIdentifier":"disk3s2", "Name":"Macintosh HD - Data", "Roles":["Data"]]]]
        ]]
        let topology = APFSPlistDecoder.decode(root)
        precondition(topology.containers.count == 1)
        precondition(topology.containers[0].physicalStores == ["disk0s2"])
        precondition(topology.containers[0].volumes.count == 2)
        precondition(topology.containers[0].volumes[0].roles == ["System"])
        precondition(APFSPlistDecoder.decode([:]).warnings.count == 1)
        precondition(APFSPlistDecoder.decode(["Containers":[["Name":"invalid"]]]).warnings.count == 1)
        print("PASS: APFS parser positive, missing-root, missing-ID fixtures")
    }
}
