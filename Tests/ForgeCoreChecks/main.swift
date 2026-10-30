import Foundation
import ForgeCheckSupport

var failures = 0
for name in ForgeCoreChecks.names {
    do {
        try ForgeCoreChecks.run(name)
        print("PASS \(name)")
    } catch {
        failures += 1
        print("FAIL \(name): \(error)")
    }
}
print("\(ForgeCoreChecks.names.count - failures)/\(ForgeCoreChecks.names.count) Forge core checks passed")
if failures > 0 { exit(1) }
