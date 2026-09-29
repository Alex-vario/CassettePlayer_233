import Foundation
import AppKit
import IOKit
import IOKit.hid
import CoreGraphics

final class MediaKeyManager {

    private var manager: IOHIDManager?

    private weak var audioPlayer: AudioPlayer?

    private var hidThread: Thread?

    private var hidRunLoop: CFRunLoop?

    private var eventTap: CFMachPort?

    private var eventTapSource: CFRunLoopSource?

    private let runLoopReady =
        DispatchSemaphore(
            value: 0
        )

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

        hidThread =
            thread

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

            // =====================================================
            // CGEventTap
            // =====================================================
            //
            // Системные media-key события macOS имеют type = 14.
            //
            // Для Play/Pause нашего JLab:
            //
            // keyCode = 16
            // state   = 0x0A — нажатие
            // state   = 0x0B — отпускание
            //
            // Здесь мы поглощаем ТОЛЬКО событие нажатия Play/Pause.
            //
            // IOHIDManager ниже продолжает самостоятельно получать
            // JLab и управлять CassettePlayer.
            //
            let systemDefinedEventMask =
                CGEventMask(
                    1 << 14
                )

            let eventTapContext =
                Unmanaged.passUnretained(
                    self
                ).toOpaque()

            if let tap =
                    CGEvent.tapCreate(
                        tap: .cghidEventTap,
                        place: .headInsertEventTap,
                        options: .defaultTap,
                        eventsOfInterest:
                            systemDefinedEventMask,
                        callback: {
                            _,
                            type,
                            event,
                            userInfo in

                            guard let userInfo else {
                                return Unmanaged.passUnretained(
                                    event
                                )
                            }

                            let mediaKeyManager =
                                Unmanaged<MediaKeyManager>
                                    .fromOpaque(
                                        userInfo
                                    )
                                    .takeUnretainedValue()

                            return
                                mediaKeyManager
                                    .handleSystemDefinedEvent(
                                        type: type,
                                        event: event
                                    )
                        },
                        userInfo: eventTapContext
                    ) {

            eventTap =
                tap

            guard let source =
                    CFMachPortCreateRunLoopSource(
                        kCFAllocatorDefault,
                        tap,
                        0
                    )
            else {

                print(
                    "MediaKeyManager: не удалось создать CGEventTap RunLoop Source"
                )

                eventTap = nil
                CGEvent.tapEnable(
                    tap: tap,
                    enable: false
                )

                return
            }

            eventTapSource =
                source

            CFRunLoopAddSource(
                runLoop,
                source,
                .commonModes
            )

            CGEvent.tapEnable(
                tap: tap,
                enable: true
            )

            print(
                "MediaKeyManager: системный Play/Pause перехватывается"
            )
            } else {

                print(
                    "MediaKeyManager: CGEventTap не удалось создать"
                )

                print(
                    "MediaKeyManager: возможно, требуется разрешение Accessibility"
                )

                // IOHID всё равно запускаем.
                // Даже если CGEventTap недоступен,
                // глобальные JLab-клавиши продолжат работать.
                eventTap = nil
            }

            // =====================================================
            // IOHIDManager
            // =====================================================

            let hidManager =
                IOHIDManagerCreate(
                    kCFAllocatorDefault,
                    IOOptionBits(
                        kIOHIDOptionsTypeNone
                    )
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
                {
                    context,
                    _,
                    _,
                    value in

                    guard let context else {
                        return
                    }

                    let mediaKeyManager =
                        Unmanaged<MediaKeyManager>
                            .fromOpaque(
                                context
                            )
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
                    IOOptionBits(
                        kIOHIDOptionsTypeNone
                    )
                )

            print(
                "MediaKeyManager: IOHIDManagerOpen = \(status)"
            )

            runLoopReady.signal()

            guard status ==
                    kIOReturnSuccess
            else {

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

            // =====================================================
            // Завершение CGEventTap
            // =====================================================

            if let source =
                    eventTapSource {

                CFRunLoopRemoveSource(
                    runLoop,
                    source,
                    .commonModes
                )
            }

            if let tap =
                    eventTap {

                CGEvent.tapEnable(
                    tap: tap,
                    enable: false
                )
            }

            eventTapSource =
                nil

            eventTap =
                nil

            // =====================================================
            // Завершение IOHIDManager
            // =====================================================

            IOHIDManagerUnscheduleFromRunLoop(
                hidManager,
                runLoop,
                CFRunLoopMode.defaultMode.rawValue
            )

            IOHIDManagerClose(
                hidManager,
                IOOptionBits(
                    kIOHIDOptionsTypeNone
                )
            )

            manager =
                nil
        }
    }

    // =============================================================
    // CGEventTap
    // =============================================================

    private func handleSystemDefinedEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        // Нас интересуют только systemDefined.
        guard type.rawValue ==
                14
        else {

            return Unmanaged.passUnretained(
                event
            )
        }

        // Из CGEvent получаем data1 тем же способом,
        // который мы только что проверили диагностикой.
        //
        // Для нашего JLab:
        //
        // Play/Pause press:
        // 1051136 = 0x100A00
        //
        // Play/Pause release:
        // 1051392 = 0x100B00
        //
        // ВАЖНО:
        //
        // В диагностике мы получали data1 через NSEvent.
        // CGEventField.mouseEventNumber здесь не является
        // настоящим systemDefined data1.
        //
        // Поэтому для надёжности получаем NSEvent-представление.
        //
        guard let nsEvent =
                NSEvent(
                    cgEvent: event
                )
        else {

            return Unmanaged.passUnretained(
                event
            )
        }

        let systemData1 =
            nsEvent.data1

        let keyCode =
            (systemData1 >> 16) & 0xFFFF

        let keyData =
            systemData1 & 0xFFFF

        let keyState =
            (keyData >> 8) & 0xFF

        // Наш JLab Play/Pause:
        //
        // keyCode = 16
        // keyState = 0x0A при нажатии.
        //
        if keyCode ==
                16 &&
            keyState ==
                0x0A {

            print(
                "MediaKeyManager: системный Play/Pause поглощён"
            )

            DispatchQueue.main.async { [weak self] in
                self?.audioPlayer?.togglePlayPause()
            }

            // nil означает:
            // НЕ передавать событие дальше системе.
            //
            // Поэтому Apple Music не должен получить
            // этот Play/Pause.
            return nil
        }

        // Все остальные systemDefined события пропускаем.
        return Unmanaged.passUnretained(
            event
        )
    }

    // =============================================================
    // IOHID
    // =============================================================

    private func handle(
        value: IOHIDValue
    ) {

        let element =
            IOHIDValueGetElement(
                value
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

        // Consumer Control.
        guard usagePage ==
                0x0C
        else {
            return
        }

        print(
            "MediaKeyManager: HID consumer usage=0x\(String(usage, radix: 16)) value=\(integerValue)"
        )

        // Play/Pause уже обработан через CGEventTap, если он запущен.
        // Не переключаем состояние второй раз для того же нажатия.
        if usage == 0xCD && eventTap != nil {
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

        // HID callback работает на отдельном потоке.
        // AudioPlayer / SwiftUI изменяем через main queue.
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
