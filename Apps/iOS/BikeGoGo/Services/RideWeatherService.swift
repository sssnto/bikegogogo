import BikeGoGoCore
import CoreLocation
import Foundation
import WeatherKit

struct RideWeatherReading: Sendable {
    let snapshot: RideWeatherSnapshot
    let legalPageURL: URL
}

struct RideWeatherService {
    private let service = WeatherService.shared

    func weather(at point: RidePoint) async throws -> RideWeatherReading {
        let location = CLLocation(
            latitude: point.latitude,
            longitude: point.longitude
        )
        async let weather = service.weather(for: location)
        async let attribution = service.attribution
        let (result, source) = try await (weather, attribution)
        let current = result.currentWeather

        return RideWeatherReading(
            snapshot: RideWeatherSnapshot(
                temperatureCelsius: current.temperature.converted(to: .celsius).value,
                apparentTemperatureCelsius: current.apparentTemperature
                    .converted(to: .celsius).value,
                relativeHumidityPercent: current.humidity * 100,
                windSpeedKilometersPerHour: current.wind.speed
                    .converted(to: .kilometersPerHour).value,
                windDirectionDegrees: current.wind.direction
                    .converted(to: .degrees).value,
                conditionText: Self.conditionText(current.condition),
                symbolName: current.symbolName,
                capturedAt: current.date,
                latitude: point.latitude,
                longitude: point.longitude
            ),
            legalPageURL: source.legalPageURL
        )
    }

    private static func conditionText(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear:
            return "晴"
        case .partlyCloudy:
            return "局部多云"
        case .cloudy, .mostlyCloudy:
            return "多云"
        case .drizzle, .freezingDrizzle:
            return "小雨"
        case .rain, .freezingRain, .sunShowers:
            return "有雨"
        case .heavyRain:
            return "大雨"
        case .flurries, .snow, .sunFlurries:
            return "有雪"
        case .blizzard, .blowingSnow, .heavySnow:
            return "大雪"
        case .sleet, .wintryMix:
            return "雨夹雪"
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms:
            return "雷阵雨"
        case .strongStorms, .tropicalStorm, .hurricane:
            return "强风暴"
        case .foggy:
            return "有雾"
        case .haze, .smoky, .blowingDust:
            return "低能见度"
        case .breezy, .windy:
            return "有风"
        case .frigid:
            return "严寒"
        case .hot:
            return "炎热"
        case .hail:
            return "冰雹"
        }
    }
}
