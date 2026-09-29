import Foundation
import IOKit
import IOKit.hid

final class MediaKeyManager {

    private var manager: IOHIDManager?
    private weak var audioPlayer: AudioPlayer?

    private var hidThread: Thread?
    private var hidRunLoop: CFRunLoop?

    private let runLoopReady = DispatchSemaphore(value: 0)

    init(audioPlayer: AudioPlayer) {
        self.audioPlayer = audioPlayer
    }

    func start() {

        guard hidThread == nil else {
            return
        }

        let thread =
            Thread { [weak self] in
                self?.runHIDLoop()
            }

        thread.name =
            "CassettePlayer.MediaKeys"

        hidThread = thread

        thread.start()

        runLoopReady.wait()

        print(
            "MediaKeyManager: HID-поток запущен"
        )
    }

    func stop() {

        guard let hidRunLoop else {
            return
        }

        CFRunLoopStop(
            hidRunLoop
        )

        hidThread = nil
        self.hidRunLoop = nil

        print(
            "MediaKeyManager: остановлен"
        )
    }

    private func runHIDLoop() {

        autoreleasepool {

    guard let runLoop =
            CFRunLoopGetCurrent()
    else {
        print(
            "MediaKeyManager: не удалось получить HID RunLoop"
        )

        runLoopReady.signal()

        return
    }

    hidRunLoop =
        runLoop

            let hidManager =
                IOHIDManagerCreate(
                    kCFAllocatorDefault,
                    IOOptionBits(kIOHIDOptionsTypeNone)
                )

            manager =
                hidManager

            // Получаем все HID-устройства.
            //
            // Это оставляем намеренно:
            // фильтрация на уровне Device Matching
            // не находила Consumer Control JLab.
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

                    let mediaKeyManager =
                        Unmanaged<MediaKeyManager>
                            .fromOpaque(context)
                            .takeUnretainedValue()

                    mediaKeyManager.handle(
                        value: value
                    )
                },
                context
            )

            IOHIDManagerScheduleWithRunLoop(
                hidManager,
                runLoop,
                CFRunLoopMode.defaultMode.rawValue
            )

            let status =
                IOHIDManagerOpen(
                    hidManager,
                    IOOptionBits(kIOHIDOptionsTypeNone)
                )

            print(
                "MediaKeyManager: IOHIDManagerOpen = \(status)"
            )

            runLoopReady.signal()

            guard status == kIOReturnSuccess else {

                print(
                    "MediaKeyManager: IOHIDManager не открылся"
                )

                manager = nil

                CFRunLoopStop(
                    runLoop
                )

                return
            }

            print(
                "MediaKeyManager: глобальные медиа-клавиши запущены"
            )

            CFRunLoopRun()

            IOHIDManagerUnscheduleFromRunLoop(
                hidManager,
                runLoop,
                CFRunLoopMode.defaultMode.rawValue
            )

            IOHIDManagerClose(
                hidManager,
                IOOptionBits(kIOHIDOptionsTypeNone)
            )

            manager = nil
        }
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

        // Нас интересует только JLab Epic Keys.
        guard product ==
                "JLab Epic Keys"
        else {
            return
        }

        // Consumer Control.
        guard usagePage ==
                0x0C
        else {
            return
        }

        // Нас интересуют только события нажатия.
        //
        // Отпускание клавиши имеет value = 0.
        // Служебные события JLab имеют другие значения.
        guard integerValue ==
                1
        else {
            return
        }

        guard let audioPlayer else {
            return
        }

        // ВАЖНО:
        //
        // HID callback теперь работает на отдельном потоке.
        // AudioPlayer / SwiftUI изменяем через main queue,
        // чтобы не трогать состояние приложения непосредственно
        // из HID-потока.
        DispatchQueue.main.async {

            switch usage {

            case 0xCD:
                // Play / Pause
                audioPlayer.togglePlayPause()

            case 0xB6:
                // Previous Track
                audioPlayer.previous()

            case 0xB5:
                // Next Track
                audioPlayer.next()

            case 0xE9:
                // Volume Up
                let newVolume =
                    min(
                        audioPlayer.volume + 0.05,
                        1.0
                    )

                audioPlayer.setVolume(
                    newVolume
                )

            case 0xEA:
                // Volume Down
                let newVolume =
                    max(
                        audioPlayer.volume - 0.05,
                        0.0
                    )

                audioPlayer.setVolume(
                    newVolume
                )

            case 0xE2:
                // Mute
                audioPlayer.toggleMute()

            default:
                break
            }
        }
    }
}