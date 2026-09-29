import Foundation
import IOKit
import IOKit.hid

final class MediaKeyManager {

    private var manager: IOHIDManager?
    private weak var audioPlayer: AudioPlayer?

    init(audioPlayer: AudioPlayer) {
        self.audioPlayer = audioPlayer
    }

    func start() {

        guard manager == nil else {
            return
        }

        let hidManager =
            IOHIDManagerCreate(
                kCFAllocatorDefault,
                IOOptionBits(kIOHIDOptionsTypeNone)
            )

        manager = hidManager

        IOHIDManagerSetDeviceMatching(
            hidManager,
            nil
        )

        let context =
            Unmanaged.passUnretained(
                self
            ).toOpaque()

        IOHIDManagerRegisterInputValueCallback(
            hidManager,
            { context, _, _, value in

                guard let context else {
                    return
                }

                let manager =
                    Unmanaged<MediaKeyManager>
                        .fromOpaque(context)
                        .takeUnretainedValue()

                manager.handle(
                    value: value
                )
            },
            context
        )

        IOHIDManagerScheduleWithRunLoop(
            hidManager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let status =
            IOHIDManagerOpen(
                hidManager,
                IOOptionBits(kIOHIDOptionsTypeNone)
            )

        print(
            "MediaKeyManager: IOHIDManagerOpen = \(status)"
        )

        guard status == kIOReturnSuccess else {

            print(
                "MediaKeyManager: IOHIDManager не открылся"
            )

            manager = nil

            return
        }

        print(
            "MediaKeyManager: глобальные медиа-клавиши запущены"
        )
    }

    func stop() {

        guard let manager else {
            return
        }

        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        IOHIDManagerClose(
            manager,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )

        self.manager = nil

        print(
            "MediaKeyManager: остановлен"
        )
    }

    private func handle(
        value: IOHIDValue
    ) {

        let element =
            IOHIDValueGetElement(
                value
            )

        let device =
            IOHIDElementGetDevice(
                element
            )

        let usagePage =
            IOHIDElementGetUsagePage(
                element
            )

        let usage =
            IOHIDElementGetUsage(
                element
            )

        let integerValue =
            IOHIDValueGetIntegerValue(
                value
            )

        let product =
            IOHIDDeviceGetProperty(
                device,
                kIOHIDProductKey as CFString
            ) as? String
            ?? ""

        guard product == "JLab Epic Keys" else {
            return
        }

        // Consumer Control.
        guard usagePage == 0x0C else {
            return
        }

        // Нас интересуют только события нажатия.
        guard integerValue == 1 else {
            return
        }

        guard let audioPlayer else {
            return
        }

        switch usage {

        // Play / Pause
        case 0xCD:

            audioPlayer.togglePlayPause()

        // Previous Track
        case 0xB6:

            audioPlayer.previous()

        // Next Track
        case 0xB5:

            audioPlayer.next()

        // Volume Up
        case 0xE9:

            let newVolume =
                min(
                    audioPlayer.volume + 0.05,
                    1.0
                )

            audioPlayer.setVolume(
                newVolume
            )

        // Volume Down
        case 0xEA:

            let newVolume =
                max(
                    audioPlayer.volume - 0.05,
                    0.0
                )

            audioPlayer.setVolume(
                newVolume
            )

        // Mute
        case 0xE2:

            audioPlayer.toggleMute()

        default:

            break
        }
    }
}