//
//  IPhoneTextureGenerator.swift
//  gophoto
//
//  Created by Sebastian Darren on 29/10/26.
//

import UIKit
import RealityKit

enum IPhoneTextureGenerator {

    private static var cachedScreenTexture: TextureResource?
    private static var cachedBackTexture: TextureResource?

    static func getScreenTexture() -> TextureResource? {
        if let cached = cachedScreenTexture { return cached }
        guard let image = makeScreenImage(),
              let cgImage = image.cgImage else {
            return nil
        }
        let texture: TextureResource?
        if #available(iOS 18.0, *) {
            texture = try? TextureResource(image: cgImage, options: .init(semantic: .color))
        } else {
            texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color))
        }
        guard let texture else { return nil }
        cachedScreenTexture = texture
        return texture
    }

    static func getBackTexture() -> TextureResource? {
        if let cached = cachedBackTexture { return cached }
        guard let image = makeBackImage(),
              let cgImage = image.cgImage else {
            return nil
        }
        let texture: TextureResource?
        if #available(iOS 18.0, *) {
            texture = try? TextureResource(image: cgImage, options: .init(semantic: .color))
        } else {
            texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color))
        }
        guard let texture else { return nil }
        cachedBackTexture = texture
        return texture
    }

    // MARK: - Clean Mockup Screen

    static func makeScreenImage() -> UIImage? {
        let size = CGSize(width: 512, height: 1056)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let ctx = context.cgContext
            let rect = CGRect(origin: .zero, size: size)

            // 1. Clean dark screen — flat, minimal, no heavy gradients
            ctx.setFillColor(UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0).cgColor)
            ctx.fill(rect)

            // 2. Very subtle center glow for depth
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradientColors = [
                UIColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 0.35).cgColor,
                UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 0.0).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 1.0]) {
                ctx.saveGState()
                ctx.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.45),
                    startRadius: 30,
                    endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.45),
                    endRadius: size.width * 0.85,
                    options: [.drawsAfterEndLocation]
                )
                ctx.restoreGState()
            }

            // 3. Dynamic Island cutout pill
            let islandWidth: CGFloat = 114
            let islandHeight: CGFloat = 34
            let islandRect = CGRect(x: (size.width - islandWidth) / 2, y: 26, width: islandWidth, height: islandHeight)
            let islandPath = UIBezierPath(roundedRect: islandRect, cornerRadius: islandHeight / 2)
            ctx.setFillColor(UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0).cgColor)
            ctx.addPath(islandPath.cgPath)
            ctx.fillPath()

            // 4. Minimalist Camera Viewfinder Corners (GoPhoto accent)
            let frameRect = CGRect(x: 54, y: 160, width: size.width - 108, height: size.height - 360)
            drawMinimalistViewfinder(in: ctx, rect: frameRect)

            // 5. Home Indicator Bar
            let barW: CGFloat = 130
            let barH: CGFloat = 4.5
            let homeBarRect = CGRect(x: (size.width - barW) / 2, y: size.height - 32, width: barW, height: barH)
            let homeBarPath = UIBezierPath(roundedRect: homeBarRect, cornerRadius: barH / 2)
            ctx.setFillColor(UIColor(white: 1.0, alpha: 0.50).cgColor)
            ctx.addPath(homeBarPath.cgPath)
            ctx.fillPath()
        }
    }

    // MARK: - Clean Mockup Back

    static func makeBackImage() -> UIImage? {
        let size = CGSize(width: 512, height: 1056)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let ctx = context.cgContext
            let rect = CGRect(origin: .zero, size: size)

            // Flat, clean off-white / silver-grey — classic clay mockup
            ctx.setFillColor(UIColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1.0).cgColor)
            ctx.fill(rect)

            // Very subtle vignette for soft depth
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let sheenColors = [
                UIColor(white: 1.0, alpha: 0.12).cgColor,
                UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 0.30).cgColor,
            ] as CFArray
            if let grad = CGGradient(colorsSpace: colorSpace, colors: sheenColors, locations: [0.0, 1.0]) {
                ctx.drawRadialGradient(
                    grad,
                    startCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.48),
                    startRadius: 40,
                    endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                    endRadius: size.width * 0.9,
                    options: [.drawsAfterEndLocation]
                )
            }

            // Minimalist debossed Apple Logo
            let logoCenter = CGPoint(x: size.width / 2, y: size.height / 2 + 10)
            drawMinimalistAppleLogo(in: ctx, center: logoCenter, size: 52)
        }
    }

    // MARK: - Drawing Helpers

    private static func drawMinimalistViewfinder(in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        let cornerLen: CGFloat = 20
        let lineWidth: CGFloat = 1.5
        ctx.setStrokeColor(UIColor(red: 0.98, green: 0.78, blue: 0.46, alpha: 0.40).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)

        // Top-left
        ctx.beginPath()
        ctx.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLen))
        ctx.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.minX + cornerLen, y: rect.minY))
        ctx.strokePath()

        // Top-right
        ctx.beginPath()
        ctx.move(to: CGPoint(x: rect.maxX - cornerLen, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLen))
        ctx.strokePath()

        // Bottom-left
        ctx.beginPath()
        ctx.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLen))
        ctx.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        ctx.addLine(to: CGPoint(x: rect.minX + cornerLen, y: rect.maxY))
        ctx.strokePath()

        // Bottom-right
        ctx.beginPath()
        ctx.move(to: CGPoint(x: rect.maxX - cornerLen, y: rect.maxY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLen))
        ctx.strokePath()

        // Center crosshair
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let cross: CGFloat = 7
        ctx.setStrokeColor(UIColor(white: 1.0, alpha: 0.25).cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: center.x - cross, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x + cross, y: center.y))
        ctx.move(to: CGPoint(x: center.x, y: center.y - cross))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y + cross))
        ctx.strokePath()

        ctx.restoreGState()
    }

    private static func drawMinimalistAppleLogo(in ctx: CGContext, center: CGPoint, size: CGFloat) {
        ctx.saveGState()

        ctx.setFillColor(UIColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 0.55).cgColor)

        let s = size / 100.0

        // Leaf
        ctx.saveGState()
        ctx.translateBy(x: center.x + 4 * s, y: center.y - 42 * s)
        let leaf = UIBezierPath()
        leaf.move(to: .zero)
        leaf.addCurve(to: CGPoint(x: 14 * s, y: -16 * s), controlPoint1: CGPoint(x: 2 * s, y: -10 * s), controlPoint2: CGPoint(x: 8 * s, y: -15 * s))
        leaf.addCurve(to: .zero, controlPoint1: CGPoint(x: 12 * s, y: -6 * s), controlPoint2: CGPoint(x: 6 * s, y: -1 * s))
        ctx.addPath(leaf.cgPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Apple body
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)

        let body = UIBezierPath()
        body.move(to: CGPoint(x: 0, y: -26 * s))
        body.addCurve(to: CGPoint(x: 28 * s, y: -24 * s), controlPoint1: CGPoint(x: 10 * s, y: -34 * s), controlPoint2: CGPoint(x: 22 * s, y: -34 * s))
        body.addCurve(to: CGPoint(x: 34 * s, y: -4 * s), controlPoint1: CGPoint(x: 34 * s, y: -16 * s), controlPoint2: CGPoint(x: 35 * s, y: -8 * s))
        body.addCurve(to: CGPoint(x: 34 * s, y: 16 * s), controlPoint1: CGPoint(x: 24 * s, y: -2 * s), controlPoint2: CGPoint(x: 24 * s, y: 14 * s))
        body.addCurve(to: CGPoint(x: 24 * s, y: 34 * s), controlPoint1: CGPoint(x: 35 * s, y: 22 * s), controlPoint2: CGPoint(x: 32 * s, y: 32 * s))
        body.addCurve(to: CGPoint(x: 0, y: 28 * s), controlPoint1: CGPoint(x: 16 * s, y: 36 * s), controlPoint2: CGPoint(x: 8 * s, y: 34 * s))
        body.addCurve(to: CGPoint(x: -24 * s, y: 34 * s), controlPoint1: CGPoint(x: -8 * s, y: 34 * s), controlPoint2: CGPoint(x: -16 * s, y: 36 * s))
        body.addCurve(to: CGPoint(x: -34 * s, y: 0), controlPoint1: CGPoint(x: -32 * s, y: 32 * s), controlPoint2: CGPoint(x: -35 * s, y: 16 * s))
        body.addCurve(to: CGPoint(x: -28 * s, y: -24 * s), controlPoint1: CGPoint(x: -34 * s, y: -12 * s), controlPoint2: CGPoint(x: -34 * s, y: -18 * s))
        body.addCurve(to: CGPoint(x: 0, y: -26 * s), controlPoint1: CGPoint(x: -22 * s, y: -34 * s), controlPoint2: CGPoint(x: -10 * s, y: -34 * s))
        body.close()

        ctx.addPath(body.cgPath)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.restoreGState()
    }
}
