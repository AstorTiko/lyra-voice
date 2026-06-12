import CoreAudio
import Foundation

/// Микрофон (устройство ввода) системы: стабильный UID + человекочитаемое имя.
struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// Перечисление и резолвинг устройств аудио-ввода через CoreAudio.
/// Используем CoreAudio (а не AVCaptureDevice) ради совместимости со всеми
/// версиями macOS и потому что для маршрутизации в AVAudioEngine всё равно
/// нужен `AudioDeviceID`.
enum AudioInputDevices {
    /// Все устройства, у которых есть входные каналы (микрофоны).
    static func available() -> [AudioInputDevice] {
        allDeviceIDs().compactMap { id in
            guard hasInputStreams(id), let uid = deviceUID(id) else { return nil }
            let name = deviceName(id) ?? uid
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    /// `AudioDeviceID` по сохранённому UID (для маршрутизации записи).
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        available().first(where: { $0.uid == uid })?.id
    }

    /// Имя устройства по UID — для подписи в настройках.
    static func name(forUID uid: String) -> String? {
        available().first(where: { $0.uid == uid })?.name
    }

    // MARK: - CoreAudio

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }
        return ids
    }

    private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return false
        }
        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, bufferList) == noErr else {
            return false
        }
        let list = bufferList.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func deviceUID(_ id: AudioDeviceID) -> String? {
        stringProperty(id, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        stringProperty(id, selector: kAudioObjectPropertyName)
    }

    private static func stringProperty(_ id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, ptr)
        }
        guard status == noErr else { return nil }
        return value as String?
    }
}
