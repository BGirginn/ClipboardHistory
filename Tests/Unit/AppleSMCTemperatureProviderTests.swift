import XCTest

@testable import ClipboardHistory

final class AppleSMCTemperatureProviderTests: XCTestCase {
    func testSMCCodeConversionClassificationAndNames() throws {
        let provider = AppleSMCTemperatureProvider()
        let sp78 = try XCTUnwrap(provider.fourCharacterCode("sp78"))
        let fpe2 = try XCTUnwrap(provider.fourCharacterCode("fpe2"))
        let float = try XCTUnwrap(provider.fourCharacterCode("flt "))

        XCTAssertNil(provider.fourCharacterCode("bad"))
        XCTAssertEqual(provider.fourCharacterString(sp78), "sp78")
        XCTAssertEqual(provider.fourCharacterString(0xFFFF_FFFF), "")
        XCTAssertTrue(provider.isTemperatureType(sp78))
        XCTAssertTrue(provider.isTemperatureType(fpe2))
        XCTAssertTrue(provider.isTemperatureType(float))
        XCTAssertFalse(provider.isTemperatureType(0))
        XCTAssertTrue(provider.isCPUKey("Tp01"))
        XCTAssertTrue(provider.isCPUKey("Te05"))
        XCTAssertTrue(provider.isCPUKey("TC0P"))
        XCTAssertFalse(provider.isCPUKey("TG0P"))
        XCTAssertTrue(provider.sensorName(for: "Te05").contains("Te05"))
        XCTAssertTrue(provider.sensorName(for: "Tp01").contains("Tp01"))
        XCTAssertTrue(provider.sensorName(for: "TC0P").contains("TC0P"))
        XCTAssertEqual(provider.uint32(from: [1, 2, 3]), 0)
        XCTAssertEqual(provider.uint32(from: [1, 2, 3, 4]), 0x0102_0304)
    }

    func testTemperatureDecodersCoverSignedFixedPointAndFloatFormats() throws {
        let provider = AppleSMCTemperatureProvider()
        let sp78 = try XCTUnwrap(provider.fourCharacterCode("sp78"))
        let fpe2 = try XCTUnwrap(provider.fourCharacterCode("fpe2"))
        let floatType = try XCTUnwrap(provider.fourCharacterCode("flt "))
        let floatBits = Float(42.5).bitPattern.bigEndian
        let floatBytes = withUnsafeBytes(of: floatBits) { Array($0) }

        XCTAssertEqual(provider.decodeTemperature(dataType: sp78, bytes: [0x2A, 0x80]), 42.5)
        XCTAssertEqual(provider.decodeTemperature(dataType: sp78, bytes: [0xFF, 0x00]), -1)
        XCTAssertNil(provider.decodeTemperature(dataType: sp78, bytes: [0x2A]))
        XCTAssertEqual(provider.decodeTemperature(dataType: fpe2, bytes: [0x00, 0xAA]), 42.5)
        XCTAssertNil(provider.decodeTemperature(dataType: fpe2, bytes: []))
        XCTAssertEqual(
            try XCTUnwrap(provider.decodeTemperature(dataType: floatType, bytes: floatBytes)),
            42.5,
            accuracy: 0.001
        )
        XCTAssertNil(provider.decodeTemperature(dataType: floatType, bytes: [0, 1, 2]))
        XCTAssertNil(provider.decodeTemperature(dataType: 0, bytes: [0, 0, 0, 0]))
    }
}
